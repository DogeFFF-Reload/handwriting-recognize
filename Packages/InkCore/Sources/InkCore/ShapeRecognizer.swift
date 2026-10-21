#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

/// 几何草图 → 图形：双击、选「几何」后，把这一段笔迹认成标准的平面或立体图形。
///
/// 1. 每一笔：重采样，判断是不是封闭的，按转角找拐点，拆成直的线段和弯的弧；
///    封闭的一笔，拐点 ≥ 3 个是多边形，没有明显拐点就拟合二次曲线（椭圆、圆）。
/// 2. 立体图形先认：圆 + 里面一道「赤道」是球；上下两个椭圆（下面常常只画半个）+ 两侧两条线是圆柱；
///    一个椭圆 + 两条交于一点的线是圆锥；直线（含封闭多边形的边）连成的图有 8 个顶点、三组平行棱是长方体 / 正方体，
///    6 个顶点三条平行侧棱是三棱柱，5 个顶点是四棱锥，4 个顶点两两相连（带一条虚线）是三棱锥。
///    手画的虚线是一串短线，先按共线连起来。
/// 3. 剩下的是平面图形：多边形按边长、角度认成正方形、矩形、菱形、平行四边形、梯形、等边 / 等腰 / 直角三角形、
///    正多边形，并把手抖的地方修正（直角就是直角，接近水平的边放平）；几笔直线首尾相接围成一圈也算多边形；
///    其余直线是线段。
public enum ShapeRecognizer {
    /// 认不出来返回空数组。
    public static func recognize(strokes: [InkStroke]) -> [Figure] {
        var prims: [Prim] = []
        for s in strokes { prims += analyze(s.points) }
        guard !prims.isEmpty else { return [] }
        prims = mergeDashes(prims)

        if let (solid, used) = sphere(prims) ?? cylinder(prims) ?? cone(prims) ?? polyhedron(prims) {
            // 立体图形范围里的零碎笔画（虚线、半径、高）都算它的
            let box = solid.bounds.insetBy(dx: -12, dy: -12)
            let rest = prims.indices.filter { !used.contains($0) && !box.contains(prims[$0].bounds) }
            return [solid] + planar(rest.map { prims[$0] })
        }
        return planar(prims)
    }

    // MARK: - 一笔拆成基本元素

    struct Prim {
        enum Kind { case line, arc, polygon, curve }
        var kind: Kind
        var points: [CGPoint]
        /// 线段两端。
        var a: CGPoint = .zero
        var b: CGPoint = .zero
        /// 多边形顶点（顺时针）。
        var vertices: [CGPoint] = []
        /// 曲线（封闭的椭圆，或拟合得上的弧）。
        var ellipse: Ellipse2?
        var dashed = false

        var bounds: CGRect {
            switch kind {
            case .line: return Geo.bounds([a, b])
            case .polygon: return Geo.bounds(vertices)
            default: return Geo.bounds(points)
            }
        }

        var length: CGFloat { Geo.dist(a, b) }

        static func line(_ a: CGPoint, _ b: CGPoint, dashed: Bool = false) -> Prim {
            var p = Prim(kind: .line, points: [a, b])
            p.a = a
            p.b = b
            p.dashed = dashed
            return p
        }
    }

    static func analyze(_ raw: [CGPoint]) -> [Prim] {
        var pts: [CGPoint] = []
        for p in raw where pts.last.map({ Geo.dist($0, p) > 0.5 }) ?? true { pts.append(p) }
        guard pts.count >= 2 else { return [] }
        let box = Geo.bounds(pts)
        let diag = hypot(box.width, box.height)
        guard diag >= 4 else { return [] }
        let spacing = max(1.2, diag / 60)
        let r = resample(pts, spacing)
        guard r.count >= 3 else { return [.line(pts.first!, pts.last!)] }
        let length = pathLength(r)
        let side = max(box.width, box.height)

        // 封闭：后半段回到了起点附近（收尾多画过头也算）、绕了一圈、围出面积
        let tailStart = max(Int(Double(r.count) * 0.6), 4)
        let back = (tailStart..<r.count).min { Geo.dist(r[$0], r[0]) < Geo.dist(r[$1], r[0]) }
        if r.count >= 10, let k = back, Geo.dist(r[k], r[0]) <= max(14, 0.22 * side) {
            var loop = Array(r[0...k])
            let loopBox = Geo.bounds(loop)
            if pathLength(loop) > 1.9 * max(loopBox.width, loopBox.height),
               abs(Geo.signedArea(loop)) > 0.15 * loopBox.width * loopBox.height {
                // 没合上：补一小段
                if Geo.dist(loop.last!, loop.first!) > spacing { loop += resample([loop.last!, loop.first!], spacing).dropFirst().dropLast() }
                return [closedPrim(loop)].compactMap { $0 }
            }
        }

        // 不封闭：在拐点处断开，直的是线段，弯的是弧。两头 8% 以内的「拐点」是起笔、收笔的小钩，不算
        let margin = max(2, Int(Double(r.count) * 0.08))
        let cs = corners(r, closed: false).filter { $0 >= margin && $0 <= r.count - 1 - margin }
        let cuts = [0] + cs + [r.count - 1]
        var out: [Prim] = []
        for (i, j) in zip(cuts, cuts.dropFirst()) where j > i {
            let piece = Array(r[i...j])
            let chord = Geo.dist(piece.first!, piece.last!)
            guard chord > 3 || pathLength(piece) > 6 else { continue }
            if isStraight(piece) {
                let (a, b) = fitLine(piece)
                out.append(.line(a, b))
            } else {
                var arc = Prim(kind: .arc, points: piece)
                if let (e, err) = fitEllipse(piece), err < 0.08 { arc.ellipse = e }
                out.append(arc)
            }
        }
        // 相邻两段直线几乎在一条线上（手抖出来的假拐点）：并回一条
        var k = 1
        while k < out.count {
            let p = out[k - 1], q = out[k]
            if p.kind == .line, q.kind == .line, Geo.directionGap(p.a, p.b, q.a, q.b) < 12 {
                out[k - 1] = .line(p.a, q.b)
                out.remove(at: k)
            } else {
                k += 1
            }
        }
        // 断成好几段、大半是弯的：是乱涂，不是图形（一笔画的 U 形圆柱侧面只有三段）
        if out.count >= 4 {
            let curvy = out.filter { $0.kind == .arc }.map { pathLength($0.points) }.reduce(0, +)
            if curvy > 0.35 * length { return [] }
        }
        return out
    }

    /// 直的：弦长和弧长差不多，而且中间鼓出来不超过弦长的 6%（扁的半个椭圆弦长比也能到 0.9 以上）。
    static func isStraight(_ piece: [CGPoint]) -> Bool {
        let len = pathLength(piece)
        guard len > 0, let a = piece.first, let b = piece.last else { return true }
        let chord = Geo.dist(a, b)
        guard chord / len >= 0.93 else { return false }
        let bulge = piece.map { GeometrySketchRecognizer.pointLineDistance($0, a, b) }.max() ?? 0
        return bulge <= max(4, 0.06 * chord)
    }

    /// 封闭的一笔：多边形或椭圆。
    static func closedPrim(_ r: [CGPoint]) -> Prim? {
        let cs = corners(r, closed: true)
        let fit = fitEllipse(r)
        if cs.count >= 3 {
            let v = refineVertices(r, cs)
            let straight = sideStraightness(r, cs)
            // 边是弯的、椭圆又拟合得很好：其实是椭圆（拐点是手抖）
            if straight < 0.9, let (e, err) = fit, err < 0.05 {
                var p = Prim(kind: .curve, points: r)
                p.ellipse = e
                return p
            }
            guard straight >= 0.82, v.count >= 3 else { return nil }
            var p = Prim(kind: .polygon, points: r)
            p.vertices = Geo.signedArea(v) < 0 ? v.reversed() : v
            return p
        }
        guard let (e, err) = fit, err < 0.09 else { return nil }
        var p = Prim(kind: .curve, points: r)
        p.ellipse = e
        return p
    }

    // MARK: - 曲线工具

    static func pathLength(_ p: [CGPoint]) -> CGFloat {
        guard p.count > 1 else { return 0 }
        var s: CGFloat = 0
        for i in 1..<p.count { s += Geo.dist(p[i - 1], p[i]) }
        return s
    }

    /// 按弧长等距重采样。
    static func resample(_ p: [CGPoint], _ step: CGFloat) -> [CGPoint] {
        guard let first = p.first else { return [] }
        var out = [first]
        var carry: CGFloat = 0
        for i in 1..<p.count {
            var a = p[i - 1]
            let b = p[i]
            var d = Geo.dist(a, b)
            while carry + d >= step {
                let t = (step - carry) / d
                let q = CGPoint(x: a.x + t * (b.x - a.x), y: a.y + t * (b.y - a.y))
                out.append(q)
                a = q
                d = Geo.dist(a, b)
                carry = 0
            }
            carry += d
        }
        if let last = p.last, Geo.dist(out.last!, last) > step * 0.3 { out.append(last) }
        return out
    }

    /// 拐点：前后各取约 5% 弧长，方向转过 29° 以上、是附近转得最多的点，而且转角集中（尖的）。
    static func corners(_ r: [CGPoint], closed: Bool) -> [Int] {
        let n = r.count
        // 窗口至少 8 pt：一两 pt 的手抖不会被当成拐弯
        let step = max(n > 1 ? Geo.dist(r[0], r[1]) : 1, 0.5)
        let w = max(2, Int((Double(n) * 0.05).rounded()), Int((8 / step).rounded(.up)))
        guard n > 2 * w + 1 else { return [] }
        func at(_ i: Int) -> CGPoint { r[(i % n + n) % n] }
        var turn = [Double](repeating: 0, count: n)
        let range = closed ? 0..<n : w..<(n - w)
        for i in range {
            let p = at(i - w), q = at(i), s = at(i + w)
            let a1 = atan2(q.y - p.y, q.x - p.x), a2 = atan2(s.y - q.y, s.x - q.x)
            var d = abs(Double(a2 - a1))
            if d > .pi { d = 2 * .pi - d }
            turn[i] = d
        }
        // 尖的拐点：大部分转角集中在一半的窗口里（平滑的弯，比如波浪、圆，转角是摊开的）
        let h = max(1, w / 2)
        func sharp(_ i: Int) -> Bool {
            let p = at(i - h), q = at(i), s = at(i + h)
            let a1 = atan2(q.y - p.y, q.x - p.x), a2 = atan2(s.y - q.y, s.x - q.x)
            var d = abs(Double(a2 - a1))
            if d > .pi { d = 2 * .pi - d }
            return d >= 0.6 * turn[i]
        }
        var out: [Int] = []
        // 29°：钝角三角形（140° 多的角只转 30° 多）也认得出；圆、波浪这种平滑的弯由 sharp 挡掉
        for i in range where turn[i] > 0.5 {
            var isMax = true
            for k in -w...w where k != 0 {
                let j = closed ? (i + k + n) % n : i + k
                guard j >= 0, j < n else { continue }
                if turn[j] > turn[i] || (turn[j] == turn[i] && k < 0) { isMax = false; break }
            }
            if isMax, sharp(i) { out.append(i) }
        }
        return out
    }

    /// 拐点之间每一段的直度（弦长 / 弧长），取最差的一段。
    static func sideStraightness(_ r: [CGPoint], _ cs: [Int]) -> CGFloat {
        var worst: CGFloat = 1
        for (k, i) in cs.enumerated() {
            let j = cs[(k + 1) % cs.count]
            let piece = cyclic(r, from: i, to: j)
            let len = pathLength(piece)
            guard len > 0 else { continue }
            worst = min(worst, Geo.dist(piece.first!, piece.last!) / len)
        }
        return worst
    }

    static func cyclic(_ r: [CGPoint], from i: Int, to j: Int) -> [CGPoint] {
        j > i ? Array(r[i...j]) : Array(r[i...]) + Array(r[...j])
    }

    /// 每条边用中间那段拟合直线，相邻两条直线的交点就是顶点（比拐点那一点准）。
    static func refineVertices(_ r: [CGPoint], _ cs: [Int]) -> [CGPoint] {
        let lines: [(CGPoint, CGPoint)] = cs.indices.map { k in
            let piece = cyclic(r, from: cs[k], to: cs[(k + 1) % cs.count])
            let cut = max(1, piece.count / 6)
            let inner = piece.count > 2 * cut + 2 ? Array(piece[cut..<(piece.count - cut)]) : piece
            return fitLine(inner)
        }
        let size = hypot(Geo.bounds(r).width, Geo.bounds(r).height)
        var out: [CGPoint] = []
        for k in cs.indices {
            let raw = r[cs[k]]
            let prev = lines[(k - 1 + lines.count) % lines.count], next = lines[k]
            if let p = intersect(prev.0, prev.1, next.0, next.1), Geo.dist(p, raw) < 0.25 * size {
                out.append(p)
            } else {
                out.append(raw)
            }
        }
        return out
    }

    static func intersect(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> CGPoint? {
        let d1 = CGPoint(x: b.x - a.x, y: b.y - a.y), d2 = CGPoint(x: d.x - c.x, y: d.y - c.y)
        let den = d1.x * d2.y - d1.y * d2.x
        guard abs(den) > 1e-6 * hypot(d1.x, d1.y) * hypot(d2.x, d2.y) + 1e-9 else { return nil }
        let t = ((c.x - a.x) * d2.y - (c.y - a.y) * d2.x) / den
        return CGPoint(x: a.x + t * d1.x, y: a.y + t * d1.y)
    }

    /// 主成分方向上的直线，两端取所有点投影的最远处。
    static func fitLine(_ p: [CGPoint]) -> (CGPoint, CGPoint) {
        let m = Geo.mean(p)
        var sxx: CGFloat = 0, syy: CGFloat = 0, sxy: CGFloat = 0
        for q in p {
            sxx += (q.x - m.x) * (q.x - m.x)
            syy += (q.y - m.y) * (q.y - m.y)
            sxy += (q.x - m.x) * (q.y - m.y)
        }
        let t = 0.5 * atan2(2 * sxy, sxx - syy)
        let u = CGPoint(x: cos(t), y: sin(t))
        var lo = CGFloat.infinity, hi = -CGFloat.infinity
        for q in p {
            let s = (q.x - m.x) * u.x + (q.y - m.y) * u.y
            lo = min(lo, s)
            hi = max(hi, s)
        }
        var a = CGPoint(x: m.x + lo * u.x, y: m.y + lo * u.y), b = CGPoint(x: m.x + hi * u.x, y: m.y + hi * u.y)
        // 保持书写方向
        if let f = p.first, Geo.dist(f, b) < Geo.dist(f, a) { swap(&a, &b) }
        return (a, b)
    }

    /// 二次曲线拟合 A x² + B xy + C y² + D x + E y = 1（坐标先移到质心、缩放），要求是椭圆。
    /// 返回椭圆和平均几何误差（相对半轴的平均值）。
    static func fitEllipse(_ pts: [CGPoint]) -> (Ellipse2, CGFloat)? {
        guard pts.count >= 6 else { return nil }
        let m = Geo.mean(pts)
        let box = Geo.bounds(pts)
        let s = Double(max(box.width, box.height, 1)) / 2
        var N = [[Double]](repeating: [Double](repeating: 0, count: 5), count: 5)
        var rhs = [Double](repeating: 0, count: 5)
        for p in pts {
            let x = Double(p.x - m.x) / s, y = Double(p.y - m.y) / s
            let row = [x * x, x * y, y * y, x, y]
            for i in 0..<5 {
                rhs[i] += row[i]
                for j in 0..<5 { N[i][j] += row[i] * row[j] }
            }
        }
        guard let c = solve(N, rhs) else { return nil }
        let (A, B, C, D, E) = (c[0], c[1], c[2], c[3], c[4])
        let det = 4 * A * C - B * B
        guard det > 1e-9 else { return nil }
        let x0 = (-2 * C * D + B * E) / det, y0 = (B * D - 2 * A * E) / det
        let K = 1 + A * x0 * x0 + B * x0 * y0 + C * y0 * y0
        guard K > 0 else { return nil }
        let t = 0.5 * atan2(B, A - C)
        let lu = (A * cos(t) * cos(t) + B * sin(t) * cos(t) + C * sin(t) * sin(t)) / K
        let lv = (A * sin(t) * sin(t) - B * sin(t) * cos(t) + C * cos(t) * cos(t)) / K
        guard lu > 0, lv > 0 else { return nil }
        let a = 1 / lu.squareRoot() * s, b = 1 / lv.squareRoot() * s
        guard a.isFinite, b.isFinite, max(a, b) < 20 * s else { return nil }
        let center = CGPoint(x: m.x + CGFloat(x0 * s), y: m.y + CGFloat(y0 * s))
        let e = Ellipse2(center: center, a: CGFloat(a), b: CGFloat(b), angle: CGFloat(t), isCircle: false)
        // 误差：沿着从中心出发的射线，点到椭圆的距离
        var err: CGFloat = 0
        for p in pts {
            let d = CGPoint(x: p.x - center.x, y: p.y - center.y)
            let xu = d.x * e.u.x + d.y * e.u.y, yv = d.x * e.v.x + d.y * e.v.y
            let rho = ((xu / e.a) * (xu / e.a) + (yv / e.b) * (yv / e.b)).squareRoot()
            guard rho > 1e-9 else { continue }
            err += abs(1 - 1 / rho) * hypot(d.x, d.y)
        }
        return (e, err / CGFloat(pts.count) / ((e.a + e.b) / 2))
    }

    /// 高斯消元（列主元）。
    static func solve(_ m: [[Double]], _ b: [Double]) -> [Double]? {
        let n = b.count
        var a = m
        var x = b
        for col in 0..<n {
            guard let piv = (col..<n).max(by: { abs(a[$0][col]) < abs(a[$1][col]) }), abs(a[piv][col]) > 1e-12 else { return nil }
            a.swapAt(col, piv)
            x.swapAt(col, piv)
            for r in (col + 1)..<n {
                let f = a[r][col] / a[col][col]
                for c in col..<n { a[r][c] -= f * a[col][c] }
                x[r] -= f * x[col]
            }
        }
        var out = [Double](repeating: 0, count: n)
        for r in stride(from: n - 1, through: 0, by: -1) {
            var s = x[r]
            for c in (r + 1)..<n { s -= a[r][c] * out[c] }
            out[r] = s / a[r][r]
        }
        return out.allSatisfy(\.isFinite) ? out : nil
    }

    // MARK: - 虚线

    /// 手画的虚线是一串共线的短线：连成一条（标成虚线）。
    static func mergeDashes(_ prims: [Prim]) -> [Prim] {
        var lines = prims.filter { $0.kind == .line }
        let others = prims.filter { $0.kind != .line }
        guard lines.count >= 2, lines.count <= 80 else { return prims }
        let longest = lines.map(\.length).max() ?? 0
        var merged = true
        while merged {
            merged = false
            outer: for i in lines.indices {
                for j in lines.indices where j > i {
                    let p = lines[i], q = lines[j]
                    guard min(p.length, q.length) < 0.35 * longest || p.dashed || q.dashed else { continue }
                    guard Geo.directionGap(p.a, p.b, q.a, q.b) < 12 else { continue }
                    let reach = max(p.length, q.length)
                    let ends = [(p.a, q.a), (p.a, q.b), (p.b, q.a), (p.b, q.b)]
                    let near = ends.map { Geo.dist($0.0, $0.1) }.min()!
                    guard near < 1.8 * reach + 6 else { continue }
                    // 两段在同一条直线上
                    let off = max(GeometrySketchRecognizer.pointLineDistance(q.a, p.a, p.b),
                                  GeometrySketchRecognizer.pointLineDistance(q.b, p.a, p.b))
                    guard off < 6 + 0.12 * reach else { continue }
                    let all = [p.a, p.b, q.a, q.b]
                    var best = (all[0], all[1]), bestD: CGFloat = -1
                    for x in all { for y in all where Geo.dist(x, y) > bestD { bestD = Geo.dist(x, y); best = (x, y) } }
                    lines[i] = .line(best.0, best.1, dashed: true)
                    lines.remove(at: j)
                    merged = true
                    break outer
                }
            }
        }
        return others + lines
    }

    // MARK: - 立体图形

    /// 椭圆或弧当作圆柱、圆锥的底面 / 顶面（斜着看的圆）。
    struct Cap {
        var index: Int
        var center: CGPoint
        var width: CGFloat
        var height: CGFloat
        var left: CGPoint
        var right: CGPoint
        var full: Bool
    }

    static func caps(_ prims: [Prim]) -> [Cap] {
        var out: [Cap] = []
        for (i, p) in prims.enumerated() {
            switch p.kind {
            case .curve:
                guard let e = p.ellipse else { continue }
                let pts = e.samples(72)
                let b = Geo.bounds(pts)
                guard b.height < 0.8 * b.width else { continue }
                out.append(Cap(index: i, center: e.center, width: b.width, height: b.height,
                               left: CGPoint(x: b.minX, y: e.center.y), right: CGPoint(x: b.maxX, y: e.center.y), full: true))
            case .arc:
                let b = Geo.bounds(p.points)
                let ends = [p.points.first!, p.points.last!].sorted { $0.x < $1.x }
                guard b.width > 20, Geo.dist(ends[0], ends[1]) > 0.7 * b.width else { continue }
                let cy = (ends[0].y + ends[1].y) / 2
                let h = 2 * max(abs(b.maxY - cy), abs(b.minY - cy))
                guard h < 0.8 * b.width, h > 0.05 * b.width else { continue }
                out.append(Cap(index: i, center: CGPoint(x: b.midX, y: cy), width: b.width, height: h,
                               left: ends[0], right: ends[1], full: false))
            default:
                continue
            }
        }
        return out
    }

    /// 从斜着看的圆的扁度估计俯仰角。
    static func pitch(of cap: Cap) -> Double {
        asin(min(max(Double(cap.height / cap.width), 0.12), 0.9))
    }

    static func lineNear(_ prims: [Prim], _ p: CGPoint, _ q: CGPoint, tol: CGFloat, excluding: Set<Int>) -> Int? {
        prims.indices.first { i in
            guard prims[i].kind == .line, !excluding.contains(i) else { return false }
            let l = prims[i]
            return (Geo.dist(l.a, p) < tol && Geo.dist(l.b, q) < tol) || (Geo.dist(l.b, p) < tol && Geo.dist(l.a, q) < tol)
        }
    }

    /// 球：一个圆，里面横着一道椭圆（或弧）当赤道。
    static func sphere(_ prims: [Prim]) -> (Figure, Set<Int>)? {
        for (i, p) in prims.enumerated() where p.kind == .curve {
            guard let e = p.ellipse, max(e.a, e.b) / min(e.a, e.b) < 1.25 else { continue }
            let r = (e.a + e.b) / 2
            for (j, q) in prims.enumerated() where j != i && (q.kind == .curve || q.kind == .arc) {
                let b = q.bounds
                guard b.width > 1.4 * r, b.width < 2.3 * r, b.height < 0.7 * b.width,
                      abs(b.midX - e.center.x) < 0.25 * r, abs(b.midY - e.center.y) < 0.45 * r else { continue }
                let tilt = asin(min(max(Double(b.height / b.width), 0.1), 0.8))
                let s = Solid3(kind: .sphere, center: e.center, dims: [Double(r)], pitch: tilt)
                return (.solid(s), [i, j])
            }
        }
        return nil
    }

    /// 圆柱：上下两个底面（宽度相近、上下对齐）+ 左右两条母线。
    static func cylinder(_ prims: [Prim]) -> (Figure, Set<Int>)? {
        let cs = caps(prims)
        for t in cs {
            for b in cs where b.index != t.index && (t.full || b.full) {
                let w = max(t.width, b.width)
                guard b.center.y - t.center.y > 0.3 * w, abs(t.width - b.width) < 0.35 * w,
                      abs(t.center.x - b.center.x) < 0.3 * w else { continue }
                let tol = 0.2 * w + 10
                guard let l = lineNear(prims, t.left, b.left, tol: tol, excluding: []),
                      let r = lineNear(prims, t.right, b.right, tol: tol, excluding: [l]) else { continue }
                let top = t.full ? t : b
                let tilt = pitch(of: top)
                let h = Double(b.center.y - t.center.y) / cos(tilt)
                let s = Solid3(kind: .cylinder, center: Geo.mid(t.center, b.center), dims: [Double(w) / 2, h], pitch: tilt)
                return (.solid(s), [t.index, b.index, l, r])
            }
        }
        return nil
    }

    /// 圆锥：一个底面 + 从底面左右两端出发、交于上方一点的两条线。
    static func cone(_ prims: [Prim]) -> (Figure, Set<Int>)? {
        for c in caps(prims) {
            let tol = 0.2 * c.width + 10
            let lines = prims.indices.filter { prims[$0].kind == .line }
            for i in lines {
                for j in lines where j != i {
                    let li = prims[i], lj = prims[j]
                    func split(_ l: Prim, _ base: CGPoint) -> CGPoint? {
                        Geo.dist(l.a, base) < tol ? l.b : Geo.dist(l.b, base) < tol ? l.a : nil
                    }
                    guard let a1 = split(li, c.left), let a2 = split(lj, c.right), Geo.dist(a1, a2) < tol else { continue }
                    let apex = Geo.mid(a1, a2)
                    guard c.center.y - apex.y > 0.4 * c.width, abs(apex.x - c.center.x) < 0.35 * c.width else { continue }
                    let tilt = pitch(of: c)
                    let h = Double(c.center.y - apex.y) / cos(tilt)
                    let s = Solid3(kind: .cone, center: Geo.mid(apex, c.center), dims: [Double(c.width) / 2, h], pitch: tilt)
                    return (.solid(s), [c.index, i, j])
                }
            }
        }
        return nil
    }

    /// 直线（含封闭多边形的边）连成的图。
    struct Graph {
        var nodes: [CGPoint] = []
        var edges: [(Int, Int, Bool)] = []   // 两端、是不是虚线
        var used: Set<Int> = []

        var degree: [Int] {
            var d = [Int](repeating: 0, count: nodes.count)
            for (a, b, _) in edges { d[a] += 1; d[b] += 1 }
            return d
        }

        func length(_ e: (Int, Int, Bool)) -> CGFloat { Geo.dist(nodes[e.0], nodes[e.1]) }
    }

    static func graph(_ prims: [Prim], only: [Int]? = nil) -> Graph {
        var segs: [(CGPoint, CGPoint, Bool, Int)] = []
        for (i, p) in prims.enumerated() where only?.contains(i) ?? true {
            switch p.kind {
            case .line: segs.append((p.a, p.b, p.dashed, i))
            case .polygon:
                for k in p.vertices.indices { segs.append((p.vertices[k], p.vertices[(k + 1) % p.vertices.count], false, i)) }
            default: break
            }
        }
        var g = Graph()
        guard !segs.isEmpty else { return g }
        let lens = segs.map { Geo.dist($0.0, $0.1) }.sorted()
        let tol = min(max(0.16 * lens[lens.count / 2], 10), 36)
        var counts: [Int] = []
        func node(_ p: CGPoint) -> Int {
            if let k = g.nodes.indices.min(by: { Geo.dist(g.nodes[$0], p) < Geo.dist(g.nodes[$1], p) }), Geo.dist(g.nodes[k], p) < tol {
                let c = CGFloat(counts[k])
                g.nodes[k] = CGPoint(x: (g.nodes[k].x * c + p.x) / (c + 1), y: (g.nodes[k].y * c + p.y) / (c + 1))
                counts[k] += 1
                return k
            }
            g.nodes.append(p)
            counts.append(1)
            return g.nodes.count - 1
        }
        for (a, b, dashed, i) in segs {
            let x = node(a), y = node(b)
            g.used.insert(i)
            guard x != y else { continue }
            if let k = g.edges.firstIndex(where: { ($0.0 == x && $0.1 == y) || ($0.0 == y && $0.1 == x) }) {
                g.edges[k].2 = g.edges[k].2 && dashed
            } else {
                g.edges.append((x, y, dashed))
            }
        }
        return g
    }

    /// 棱按方向分组（角度差 15° 以内为一组）。
    static func directionGroups(_ g: Graph) -> [[Int]] {
        var groups: [[Int]] = []
        var dirs: [Double] = []
        for (k, e) in g.edges.enumerated() {
            let a = g.nodes[e.0], b = g.nodes[e.1]
            var t = Double(atan2(b.y - a.y, b.x - a.x)) * 180 / .pi
            t = (t + 360).truncatingRemainder(dividingBy: 180)
            if let i = dirs.indices.first(where: { abs(dirs[$0] - t) < 15 || abs(abs(dirs[$0] - t) - 180) < 15 }) {
                groups[i].append(k)
            } else {
                dirs.append(t)
                groups.append([k])
            }
        }
        return groups
    }

    static func polyhedron(_ prims: [Prim]) -> (Figure, Set<Int>)? {
        let g = graph(prims)
        let V = g.nodes.count, E = g.edges.count
        guard V >= 4 else { return nil }
        let center = Geo.mean(g.nodes)
        func mean(_ ks: [Int]) -> Double {
            guard !ks.isEmpty else { return 0 }
            var total: CGFloat = 0
            for k in ks { total += g.length(g.edges[k]) }
            return Double(total) / Double(ks.count)
        }

        // 长方体 / 正方体：8 个顶点（不画看不见的棱时 7 个），棱分三组平行
        if (V == 8 && (9...12).contains(E)) || (V == 7 && E == 9) {
            let groups = directionGroups(g).filter { $0.count >= 2 }
            if groups.count == 3, groups.map(\.count).reduce(0, +) == E {
                func dir(_ ks: [Int]) -> Double {
                    let e = g.edges[ks[0]]
                    let a = g.nodes[e.0], b = g.nodes[e.1]
                    return abs(Double(atan2(abs(b.y - a.y), abs(b.x - a.x))))
                }
                let sorted = groups.sorted { dir($0) < dir($1) }
                let horizontal = sorted.first!, vertical = sorted.last!, depth = sorted[1]
                let w = mean(horizontal), h = mean(vertical), d = mean(depth)
                let solid: Solid3
                if abs(w - h) < 0.2 * max(w, h) {
                    let edge: Double = (w + h) / 2 * 1.05
                    solid = Solid3(kind: .cube, center: center, dims: [edge])
                } else {
                    // 斜着画的棱（深度）一般画短了：放大一些，限制在前面那个面短边的 0.4～2.5 倍
                    let short: Double = min(w, h)
                    let depth: Double = min(max(d * 1.6, 0.4 * short), 2.5 * short)
                    solid = Solid3(kind: .cuboid, center: center, dims: [w * 1.05, h * 1.05, depth])
                }
                return (.solid(solid), g.used)
            }
        }
        // 三棱柱：6 个顶点，三条互相平行、长短相近的侧棱
        if V == 6, (8...9).contains(E) {
            for group in directionGroups(g) where group.count == 3 {
                let ends = Set(group.flatMap { [g.edges[$0].0, g.edges[$0].1] })
                guard ends.count == 6 else { continue }
                let others = g.edges.indices.filter { !group.contains($0) }
                let solid = Solid3(kind: .prism, center: center, dims: [mean(others), mean(group)])
                return (.solid(solid), g.used)
            }
        }
        let deg = g.degree
        // 四棱锥：5 个顶点，顶点 P 连着底面四个角，P 在底面外面
        if V == 5, (7...8).contains(E), let apex = deg.indices.max(by: { deg[$0] < deg[$1] }), deg[apex] >= 3 {
            let base = g.nodes.indices.filter { $0 != apex }.map { g.nodes[$0] }
            if !Geo.contains(Geo.convexHull(base), g.nodes[apex]) {
                let baseEdges = g.edges.indices.filter { g.edges[$0].0 != apex && g.edges[$0].1 != apex }
                let baseCenter = Geo.mean(base)
                let h = Double(abs(baseCenter.y - g.nodes[apex].y)) / 0.94
                let solid = Solid3(kind: .pyramid, center: center, dims: [mean(baseEdges), max(h, 20)])
                return (.solid(solid), g.used)
            }
        }
        // 三棱锥：4 个顶点两两相连；四点凸的时候要有一条虚线（否则就是平面上的四边形加两条对角线）
        if V == 4, E == 6 {
            let hull = Geo.convexHull(g.nodes)
            if hull.count == 3 || g.edges.contains(where: { $0.2 }) {
                let solid = Solid3(kind: .tetrahedron, center: center, dims: [mean(Array(g.edges.indices))])
                return (.solid(solid), g.used)
            }
        }
        return nil
    }

    // MARK: - 平面图形

    static func planar(_ prims: [Prim]) -> [Figure] {
        var out: [Figure] = []
        for p in prims {
            switch p.kind {
            case .polygon:
                out.append(beautify(p.vertices))
            case .curve:
                if let e = p.ellipse { out.append(.ellipse(beautify(e))) }
            default:
                break
            }
        }
        // 几笔直线：首尾相接围成一圈的是多边形，其余是线段
        let lineIdx = prims.indices.filter { prims[$0].kind == .line && prims[$0].length >= 8 }
        guard !lineIdx.isEmpty else { return out }
        let g = graph(prims, only: lineIdx)
        var visited = Set<Int>()
        let deg = g.degree
        for start in g.nodes.indices where !visited.contains(start) {
            // 连通分量
            var comp: Set<Int> = [start], stack = [start]
            while let n = stack.popLast() {
                for e in g.edges where e.0 == n || e.1 == n {
                    let m = e.0 == n ? e.1 : e.0
                    if comp.insert(m).inserted { stack.append(m) }
                }
            }
            visited.formUnion(comp)
            let edges = g.edges.filter { comp.contains($0.0) }
            if comp.count >= 3, edges.count == comp.count, comp.allSatisfy({ deg[$0] == 2 }) {
                // 一圈：按顺序走一遍
                var order = [start], prev = -1, cur = start
                while order.count < comp.count {
                    guard let e = edges.first(where: { ($0.0 == cur && $0.1 != prev) || ($0.1 == cur && $0.0 != prev) }) else { break }
                    let next = e.0 == cur ? e.1 : e.0
                    prev = cur
                    cur = next
                    order.append(cur)
                }
                if order.count == comp.count {
                    var v = order.map { g.nodes[$0] }
                    if Geo.signedArea(v) < 0 { v.reverse() }
                    out.append(beautify(v))
                    continue
                }
            }
            for e in edges { out.append(.segment(g.nodes[e.0], g.nodes[e.1])) }
        }
        return out
    }

    /// 修正手抖：按边长和角度认出特殊的多边形，摆正。
    static func beautify(_ raw: [CGPoint]) -> Figure {
        var v = raw
        // 去掉几乎是平角的「顶点」（一条边分两笔画）
        while v.count > 3, let k = Geo.angles(v).firstIndex(where: { $0 > 165 }) { v.remove(at: k) }
        if Geo.signedArea(v) < 0 { v.reverse() }
        let s = Geo.sides(v), ang = Geo.angles(v)
        let n = v.count
        switch n {
        case 3:
            if s.max()! / s.min()! < 1.12 {
                return .polygon(Polygon2(vertices: regular(v, upright: true), rule: .regular))
            }
            if let k = ang.firstIndex(where: { abs($0 - 90) < 7 }) {
                // 直角：顶点挪到以斜边为直径的圆上（泰勒斯）
                let p = v[(k + 1) % 3], q = v[(k + 2) % 3]
                let m = Geo.mid(p, q), r = Geo.dist(p, q) / 2
                let legs = (Geo.dist(v[k], p), Geo.dist(v[k], q))
                var dir = Geo.unit(CGPoint(x: v[k].x - m.x, y: v[k].y - m.y))
                if abs(legs.0 - legs.1) < 0.08 * max(legs.0, legs.1) {
                    // 等腰直角：顶点在斜边的中垂线上
                    let hyp = Geo.unit(CGPoint(x: q.x - p.x, y: q.y - p.y))
                    var nrm = CGPoint(x: -hyp.y, y: hyp.x)
                    if nrm.x * dir.x + nrm.y * dir.y < 0 { nrm = CGPoint(x: -nrm.x, y: -nrm.y) }
                    dir = nrm
                }
                v[k] = CGPoint(x: m.x + dir.x * r, y: m.y + dir.y * r)
            } else if let k = (0..<3).first(where: { abs(s[($0 + 2) % 3] - s[$0]) < 0.06 * max(s[($0 + 2) % 3], s[$0]) }) {
                // 等腰：顶点 k 两边相等，挪到底边的中垂线上
                let p = v[(k + 1) % 3], q = v[(k + 2) % 3]
                let m = Geo.mid(p, q)
                let base = Geo.unit(CGPoint(x: q.x - p.x, y: q.y - p.y))
                let nrm = CGPoint(x: -base.y, y: base.x)
                let h = (v[k].x - m.x) * nrm.x + (v[k].y - m.y) * nrm.y
                v[k] = CGPoint(x: m.x + nrm.x * h, y: m.y + nrm.y * h)
            }
            return .polygon(Polygon2(vertices: levelled(v), rule: .free))
        case 4:
            if ang.allSatisfy({ abs($0 - 90) < 12 }) {
                return .polygon(rectangle(v))
            }
            let par02 = Geo.directionGap(v[0], v[1], v[2], v[3]) < 10, par13 = Geo.directionGap(v[1], v[2], v[3], v[0]) < 10
            if par02 && par13 {
                let c = Geo.mean(v)
                let d1 = CGPoint(x: (v[2].x - v[0].x) / 2, y: (v[2].y - v[0].y) / 2)
                var d2 = CGPoint(x: (v[3].x - v[1].x) / 2, y: (v[3].y - v[1].y) / 2)
                let rhombus = s.max()! / s.min()! < 1.12
                if rhombus {
                    let len = hypot(d2.x, d2.y), u = Geo.unit(d1)
                    var perp = CGPoint(x: -u.y * len, y: u.x * len)
                    if perp.x * d2.x + perp.y * d2.y < 0 { perp = CGPoint(x: -perp.x, y: -perp.y) }
                    d2 = perp
                }
                let q = [CGPoint(x: c.x - d1.x, y: c.y - d1.y), CGPoint(x: c.x - d2.x, y: c.y - d2.y),
                         CGPoint(x: c.x + d1.x, y: c.y + d1.y), CGPoint(x: c.x + d2.x, y: c.y + d2.y)]
                return .polygon(Polygon2(vertices: levelled(q), rule: rhombus ? .rhombus : .parallelogram))
            }
            if Geo.directionGap(v[0], v[1], v[2], v[3]) < 9 || Geo.directionGap(v[1], v[2], v[3], v[0]) < 9 {
                // 梯形：短的那条底边转到和长的平行
                let k = Geo.directionGap(v[0], v[1], v[2], v[3]) < 9 ? 0 : 1
                let (i, j) = s[k] >= s[k + 2] ? (k, k + 2) : (k + 2, k)
                let long = Geo.unit(CGPoint(x: v[(i + 1) % 4].x - v[i].x, y: v[(i + 1) % 4].y - v[i].y))
                let m = Geo.mid(v[j], v[(j + 1) % 4]), half = s[j] / 2
                // 对边走向相反
                v[j] = CGPoint(x: m.x + long.x * half, y: m.y + long.y * half)
                v[(j + 1) % 4] = CGPoint(x: m.x - long.x * half, y: m.y - long.y * half)
            }
            return .polygon(Polygon2(vertices: levelled(v), rule: .free))
        default:
            let target = Double(n - 2) * 180 / Double(n)
            if s.max()! / s.min()! < 1.25, ang.allSatisfy({ abs($0 - target) < 15 }) {
                return .polygon(Polygon2(vertices: regular(v, upright: false), rule: .regular))
            }
            return .polygon(Polygon2(vertices: levelled(v), rule: .free))
        }
    }

    /// 正多边形：中心、外接圆半径取平均，转到有一条边水平（三角形尖朝上）。
    static func regular(_ v: [CGPoint], upright: Bool) -> [CGPoint] {
        let n = v.count
        let c = Geo.mean(v)
        let r = v.map { Geo.dist($0, c) }.reduce(0, +) / CGFloat(n)
        var t0 = atan2(v[0].y - c.y, v[0].x - c.x)
        // 下面的边水平：顶点角度 = π/2 + π/n + 2πk/n（画布 y 向下）
        let step = 2 * CGFloat.pi / CGFloat(n)
        let base = CGFloat.pi / 2 + CGFloat.pi / CGFloat(n)
        let k = ((t0 - base) / step).rounded()
        let snapped = base + k * step
        if upright || abs(t0 - snapped) < 0.14 { t0 = snapped }
        return (0..<n).map { (i: Int) -> CGPoint in
            let t: CGFloat = t0 + step * CGFloat(i)
            return CGPoint(x: c.x + r * cos(t), y: c.y + r * sin(t))
        }
    }

    /// 四个角都接近直角：摆成矩形（边长相近就是正方形），方向接近水平就放平。
    static func rectangle(_ v: [CGPoint]) -> Polygon2 {
        // 四条边方向按 90° 周期取平均
        var sx: CGFloat = 0, sy: CGFloat = 0
        for i in 0..<4 {
            let a = v[i], b = v[(i + 1) % 4]
            let t = 4 * atan2(b.y - a.y, b.x - a.x)
            let l = Geo.dist(a, b)
            sx += l * cos(t)
            sy += l * sin(t)
        }
        var theta = atan2(sy, sx) / 4
        theta = Geo.snapAngle(theta, step: .pi / 2, within: 0.11)
        let u = CGPoint(x: cos(theta), y: sin(theta)), w = CGPoint(x: -sin(theta), y: cos(theta))
        let c = Geo.mean(v)
        var lo = (u: CGFloat.infinity, w: CGFloat.infinity), hi = (u: -CGFloat.infinity, w: -CGFloat.infinity)
        for p in v {
            let pu = (p.x - c.x) * u.x + (p.y - c.y) * u.y, pw = (p.x - c.x) * w.x + (p.y - c.y) * w.y
            lo = (min(lo.u, pu), min(lo.w, pw))
            hi = (max(hi.u, pu), max(hi.w, pw))
        }
        var width = hi.u - lo.u, height = hi.w - lo.w
        let square = abs(width - height) < 0.12 * max(width, height)
        if square {
            width = (width + height) / 2
            height = width
        }
        let midU: CGFloat = (lo.u + hi.u) / 2, midW: CGFloat = (lo.w + hi.w) / 2
        let center = CGPoint(x: c.x + midU * u.x + midW * w.x, y: c.y + midU * u.y + midW * w.y)
        // 半宽、半高方向上的两个向量，四个角 = 中心 ± 它们
        let hu = CGPoint(x: width / 2 * u.x, y: width / 2 * u.y)
        let hw = CGPoint(x: height / 2 * w.x, y: height / 2 * w.y)
        let corners: [CGPoint] = [
            CGPoint(x: center.x - hu.x - hw.x, y: center.y - hu.y - hw.y),
            CGPoint(x: center.x + hu.x - hw.x, y: center.y + hu.y - hw.y),
            CGPoint(x: center.x + hu.x + hw.x, y: center.y + hu.y + hw.y),
            CGPoint(x: center.x - hu.x + hw.x, y: center.y - hu.y + hw.y),
        ]
        return Polygon2(vertices: corners, rule: square ? .square : .rectangle)
    }

    /// 最接近水平的一条边在 6° 以内：整体转平。
    static func levelled(_ v: [CGPoint]) -> [CGPoint] {
        var best: CGFloat = .infinity
        for i in v.indices {
            let a = v[i], b = v[(i + 1) % v.count]
            var t = atan2(b.y - a.y, b.x - a.x)
            t = t - (t / .pi).rounded() * .pi
            if abs(t) < abs(best) { best = t }
        }
        guard abs(best) < 0.105, abs(best) > 1e-4 else { return v }
        let c = Geo.mean(v)
        return v.map { Geo.rotate($0, about: c, by: -best) }
    }

    /// 椭圆：接近圆就是圆；长轴放在 a；接近水平 / 竖直就摆正。
    static func beautify(_ e0: Ellipse2) -> Ellipse2 {
        var e = e0
        if max(e.a, e.b) / min(e.a, e.b) < 1.18 {
            let r = (e.a + e.b) / 2
            return Ellipse2(center: e.center, a: r, b: r, angle: 0, isCircle: true)
        }
        if e.b > e.a {
            (e.a, e.b) = (e.b, e.a)
            e.angle += .pi / 2
        }
        e.angle = e.angle - (e.angle / .pi).rounded() * .pi
        e.angle = Geo.snapAngle(e.angle, step: .pi / 2, within: 0.14)
        return e
    }
}
