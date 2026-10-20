#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

/// 几何草图 → 动态几何场景（建议 A5：笔画规则，不联网，几十毫秒）。
///
/// 只认一个模板：三角形 + 若干条中线。
/// 1. 每一笔用 Douglas–Peucker 简化成折线，拆成线段。
/// 2. 在最长的几条线段里找三条，两两求交得到三个顶点，且每条线段的两端都贴着对应的两个顶点。
/// 3. 其余线段：一端靠近某个顶点、另一端落在对边中点 15% 边长范围内，就认定为中线。
/// 认不出就返回 nil：保留原墨迹，界面说明「这张图收不进来」，不硬收成错误的三角形。
///
/// 输出和 contracts/scene-geometry.sample.json 同形：A 是最上面的点，B 左下，C 右下；
/// 中点是受约束点（role = constrained），由 relations 里的 midpoint 决定。这就是 GeoGebra 的
/// 「自由对象 / 依赖对象」分法：拖动 A、B、C，中点和中线跟着重算。
public struct GeometrySketch: Codable, Equatable {
    public struct Point: Codable, Equatable {
        public var id: String
        public var role: String   // "free" | "constrained"
        public var x: Double
        public var y: Double
    }

    public struct Object: Codable, Equatable {
        public var type: String   // "segment"
        public var id: String
        public var points: [String]
    }

    public struct Relation: Codable, Equatable {
        public var type: String   // "midpoint"
        public var of: [String]
        public var point: String
    }

    public var kind = "geometry"
    public var points: [Point]
    public var objects: [Object]
    public var relations: [Relation]

    public func jsonData() throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try enc.encode(self)
    }
}

public enum GeometrySketchRecognizer {
    struct Seg { var a: CGPoint; var b: CGPoint; var len: CGFloat { hypot(b.x - a.x, b.y - a.y) } }

    public static func recognize(strokes: [InkStroke]) -> GeometrySketch? {
        let all = strokes.flatMap(\.points)
        guard all.count >= 6 else { return nil }
        let box = bounds(all)
        let diag = hypot(box.width, box.height)
        guard diag > 40 else { return nil }

        var segs: [Seg] = []
        for s in strokes where s.points.count >= 2 {
            let sb = bounds(s.points)
            let eps = max(4, 0.05 * hypot(sb.width, sb.height))
            let poly = simplify(s.points, eps)
            for i in 1..<poly.count {
                let seg = Seg(a: poly[i - 1], b: poly[i])
                if seg.len > 0.12 * diag { segs.append(seg) }
            }
        }
        guard segs.count >= 3 else { return nil }
        let ranked = segs.sorted { $0.len > $1.len }
        let top = Array(ranked.prefix(6))

        var best: (score: CGFloat, v: [CGPoint], used: [Int])?
        for i in 0..<top.count {
            for j in (i + 1)..<top.count {
                for k in (j + 1)..<top.count {
                    guard let p1 = intersect(top[i], top[j]), let p2 = intersect(top[j], top[k]),
                          let p3 = intersect(top[k], top[i]) else { continue }
                    let area = abs((p2.x - p1.x) * (p3.y - p1.y) - (p3.x - p1.x) * (p2.y - p1.y)) / 2
                    guard area > 0.02 * diag * diag else { continue }
                    // 线段 i 连 p3-p1，j 连 p1-p2，k 连 p2-p3
                    let fits = [fit(top[i], p3, p1), fit(top[j], p1, p2), fit(top[k], p2, p3)]
                    guard fits.allSatisfy({ $0 != nil }) else { continue }
                    let score = fits.compactMap { $0 }.reduce(0, +)
                    if best == nil || score < best!.score {
                        let used = [i, j, k].map { idx in segs.firstIndex(where: { $0.a == top[idx].a && $0.b == top[idx].b })! }
                        best = (score, [p1, p2, p3], used)
                    }
                }
            }
        }
        guard let tri = best else { return nil }

        // 命名：A 最上，B 左下，C 右下
        let sortedByY = tri.v.sorted { $0.y < $1.y }
        let a = sortedByY[0]
        let rest = sortedByY.dropFirst().sorted { $0.x < $1.x }
        let named: [(String, CGPoint)] = [("A", a), ("B", rest[0]), ("C", rest[1])]
        let pos = Dictionary(uniqueKeysWithValues: named)
        let opposite: [String: (String, String)] = ["A": ("B", "C"), "B": ("C", "A"), "C": ("A", "B")]
        let avgSide = (dist(pos["A"]!, pos["B"]!) + dist(pos["B"]!, pos["C"]!) + dist(pos["C"]!, pos["A"]!)) / 3

        var points = named.map { GeometrySketch.Point(id: $0.0, role: "free", x: Double($0.1.x), y: Double($0.1.y)) }
        var objects = [
            GeometrySketch.Object(type: "segment", id: "AB", points: ["A", "B"]),
            GeometrySketch.Object(type: "segment", id: "BC", points: ["B", "C"]),
            GeometrySketch.Object(type: "segment", id: "CA", points: ["C", "A"]),
        ]
        var relations: [GeometrySketch.Relation] = []
        let midNames = ["M", "N", "P"]
        var found = Set<String>()
        for (idx, s) in segs.enumerated() where !tri.used.contains(idx) {
            for (v, p) in named where !found.contains(v) {
                let (o1, o2) = opposite[v]!
                let q1 = pos[o1]!, q2 = pos[o2]!
                let mid = CGPoint(x: (q1.x + q2.x) / 2, y: (q1.y + q2.y) / 2)
                let side = dist(q1, q2)
                let nearV = { (x: CGPoint) in dist(x, p) < 0.18 * avgSide }
                let nearMid = { (x: CGPoint) in dist(x, mid) < 0.15 * side }
                guard (nearV(s.a) && nearMid(s.b)) || (nearV(s.b) && nearMid(s.a)) else { continue }
                let m = midNames[found.count]
                found.insert(v)
                points.append(.init(id: m, role: "constrained", x: Double(mid.x), y: Double(mid.y)))
                objects.append(.init(type: "segment", id: "median_\(v)", points: [v, m]))
                relations.append(.init(type: "midpoint", of: [o1, o2], point: m))
                break
            }
        }
        return GeometrySketch(points: points, objects: objects, relations: relations)
    }

    // 线段两端分别贴着 p、q（顺序不限）时返回偏差，否则 nil
    static func fit(_ s: Seg, _ p: CGPoint, _ q: CGPoint) -> CGFloat? {
        let tol = max(18, 0.25 * s.len)
        let d1 = dist(s.a, p) + dist(s.b, q), d2 = dist(s.a, q) + dist(s.b, p)
        let d = min(d1, d2)
        let ok = d1 <= d2 ? (dist(s.a, p) < tol && dist(s.b, q) < tol) : (dist(s.a, q) < tol && dist(s.b, p) < tol)
        return ok ? d : nil
    }

    static func intersect(_ s: Seg, _ t: Seg) -> CGPoint? {
        let d1 = CGPoint(x: s.b.x - s.a.x, y: s.b.y - s.a.y), d2 = CGPoint(x: t.b.x - t.a.x, y: t.b.y - t.a.y)
        let den = d1.x * d2.y - d1.y * d2.x
        guard abs(den) > 1e-6 * s.len * t.len * 10 else { return nil }
        let u = ((t.a.x - s.a.x) * d2.y - (t.a.y - s.a.y) * d2.x) / den
        return CGPoint(x: s.a.x + u * d1.x, y: s.a.y + u * d1.y)
    }

    static func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

    static func bounds(_ pts: [CGPoint]) -> CGRect {
        var r = CGRect(origin: pts[0], size: .zero)
        for p in pts { r = r.union(CGRect(origin: p, size: .zero)) }
        return r
    }

    /// Douglas–Peucker
    static func simplify(_ pts: [CGPoint], _ eps: CGFloat) -> [CGPoint] {
        guard pts.count > 2 else { return pts }
        let a = pts.first!, b = pts.last!
        var idx = 0
        var dmax: CGFloat = 0
        for i in 1..<(pts.count - 1) {
            let d = pointLineDistance(pts[i], a, b)
            if d > dmax { dmax = d; idx = i }
        }
        if dmax > eps {
            let left = simplify(Array(pts[0...idx]), eps)
            let right = simplify(Array(pts[idx...]), eps)
            return Array(left.dropLast()) + right
        }
        return [a, b]
    }

    static func pointLineDistance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let l = dist(a, b)
        if l < 1e-6 { return dist(p, a) }
        return abs((b.x - a.x) * (a.y - p.y) - (a.x - p.x) * (b.y - a.y)) / l
    }
}
