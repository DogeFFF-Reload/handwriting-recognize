#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

// 几何图形：双击选「几何」后从草图认出来的平面图形和立体图形，以及拖关键点（节点）时怎么变。
// 坐标都是画布 point（y 向下）。立体图形存的是真正的三维尺寸和视角，用正交投影画到画布上，
// 看不见的棱画虚线（课本的画法）。这里不依赖 UIKit，拖动、测量、投影都能在 Linux / Windows 上单测。

/// 三维向量（立体图形的模型坐标：x 向右、y 向上、z 朝向看的人）。
public struct Vec3: Equatable {
    public var x, y, z: Double

    public init(_ x: Double, _ y: Double, _ z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    static func + (a: Vec3, b: Vec3) -> Vec3 { Vec3(a.x + b.x, a.y + b.y, a.z + b.z) }
    static func - (a: Vec3, b: Vec3) -> Vec3 { Vec3(a.x - b.x, a.y - b.y, a.z - b.z) }
    static func * (a: Vec3, k: Double) -> Vec3 { Vec3(a.x * k, a.y * k, a.z * k) }
    func dot(_ b: Vec3) -> Double { x * b.x + y * b.y + z * b.z }
    func cross(_ b: Vec3) -> Vec3 { Vec3(y * b.z - z * b.y, z * b.x - x * b.z, x * b.y - y * b.x) }
    var length: Double { dot(self).squareRoot() }
    var normalized: Vec3 { length > 0 ? self * (1 / length) : self }
}

/// 多边形：三角形、四边形、正多边形……顶点按画布上顺时针排（有向面积为正）。
public struct Polygon2: Equatable, Codable {
    /// 拖顶点时保持的性质。
    public enum Rule: String, Equatable, Codable {
        /// 顶点随便拖，名字跟着现在的样子变（拖成直角就叫直角三角形）。
        case free
        case square, rectangle, rhombus, parallelogram
        /// 正多边形（含等边三角形）：拖一个顶点 = 绕中心转 + 缩放。
        case regular
    }

    public var vertices: [CGPoint]
    public var rule: Rule
    /// 顶点的字母（A、B、C…），和 vertices 一一对应。
    public var labels: [String]
    /// 朝向（弧度）：旋转手柄在这个方向的「上方」。矩形、正方形就是 AB 边的方向。
    public var orientation: CGFloat

    public init(vertices: [CGPoint], rule: Rule, labels: [String]? = nil, orientation: CGFloat? = nil) {
        var v = vertices
        if Geo.signedArea(v) < 0 { v.reverse() }
        self.vertices = v
        self.rule = rule
        self.labels = labels ?? Polygon2.defaultLabels(v)
        if let orientation {
            self.orientation = orientation
        } else if rule == .square || rule == .rectangle, v.count == 4 {
            self.orientation = atan2(v[1].y - v[0].y, v[1].x - v[0].x)
        } else {
            self.orientation = 0
        }
    }

    /// 课本的叫法：三角形 A 在最上面、逆时针 B、C；四边形 A 在左上、逆时针 B、C、D。
    static func defaultLabels(_ v: [CGPoint]) -> [String] {
        guard !v.isEmpty else { return [] }
        let start: Int
        if v.count == 3 {
            start = v.indices.min { v[$0].y < v[$1].y }!
        } else {
            start = v.indices.min { v[$0].x + v[$0].y < v[$1].x + v[$1].y }!
        }
        var labels = Array(repeating: "", count: v.count)
        let letters = ["A", "B", "C", "D", "E", "F", "G", "H"]
        for k in 0..<v.count {
            // 存的是顺时针，逆时针就是下标往回走
            labels[(start - k + v.count) % v.count] = letters[k % letters.count]
        }
        return labels
    }

    public var centroid: CGPoint { Geo.mean(vertices) }
}

/// 椭圆（圆是 a = b 的椭圆）。
public struct Ellipse2: Equatable, Codable {
    public var center: CGPoint
    /// 沿 angle 方向的半轴。
    public var a: CGFloat
    /// 垂直方向的半轴。
    public var b: CGFloat
    /// 弧度。
    public var angle: CGFloat
    /// 圆：拖边上的点只改半径。
    public var isCircle: Bool

    public init(center: CGPoint, a: CGFloat, b: CGFloat, angle: CGFloat, isCircle: Bool) {
        self.center = center
        self.a = a
        self.b = b
        self.angle = angle
        self.isCircle = isCircle
    }

    var u: CGPoint { CGPoint(x: cos(angle), y: sin(angle)) }
    var v: CGPoint { CGPoint(x: -sin(angle), y: cos(angle)) }

    public func point(at t: CGFloat) -> CGPoint {
        let ca: CGFloat = a * cos(t), sb: CGFloat = b * sin(t)
        let du = u, dv = v
        return CGPoint(x: center.x + ca * du.x + sb * dv.x, y: center.y + ca * du.y + sb * dv.y)
    }

    /// 一圈上等分的 n 个点（画轮廓、算范围用）。
    public func samples(_ n: Int) -> [CGPoint] {
        let step: CGFloat = 2 * CGFloat.pi / CGFloat(n)
        var out: [CGPoint] = []
        for i in 0..<n { out.append(point(at: step * CGFloat(i))) }
        return out
    }

    /// 两个焦点（长轴上）。圆的焦点就是圆心。
    public var foci: (CGPoint, CGPoint) {
        let major = max(a, b), minor = min(a, b)
        let c = (major * major - minor * minor).squareRoot()
        let dir = a >= b ? u : v
        return (CGPoint(x: center.x - c * dir.x, y: center.y - c * dir.y), CGPoint(x: center.x + c * dir.x, y: center.y + c * dir.y))
    }
}

/// 立体图形：真正的三维尺寸 + 视角，正交投影到画布上。
public struct Solid3: Equatable, Codable {
    public enum Kind: String, Equatable, CaseIterable, Codable {
        case cube, cuboid, cylinder, cone, sphere, prism, pyramid, tetrahedron

        public var name: String {
            switch self {
            case .cube: return "正方体"
            case .cuboid: return "长方体"
            case .cylinder: return "圆柱"
            case .cone: return "圆锥"
            case .sphere: return "球"
            case .prism: return "正三棱柱"
            case .pyramid: return "正四棱锥"
            case .tetrahedron: return "正四面体"
            }
        }
    }

    public var kind: Kind
    /// 立体中心投影到画布上的位置。
    public var center: CGPoint
    /// 尺寸（point）：cube [棱长]；cuboid [长（x）, 高（y）, 宽（z）]；cylinder、cone [底面半径, 高]；
    /// sphere [半径]；prism [底面边长, 高]；pyramid [底面边长, 高]；tetrahedron [棱长]。
    public var dims: [Double]
    /// 绕竖直轴转（弧度）。
    public var yaw: Double
    /// 俯仰（弧度，正的是从上往下看）。
    public var pitch: Double

    public static let defaultYaw = -0.58
    public static let defaultPitch = 0.36

    public init(kind: Kind, center: CGPoint, dims: [Double], yaw: Double = Solid3.defaultYaw, pitch: Double = Solid3.defaultPitch) {
        self.kind = kind
        self.center = center
        self.dims = dims
        self.yaw = yaw
        self.pitch = pitch
    }
}

/// 一个几何图形。
/// 可以存进文件（草稿里的几何图形）。
public enum Figure: Equatable, Codable {
    case segment(CGPoint, CGPoint)
    case polygon(Polygon2)
    case ellipse(Ellipse2)
    case solid(Solid3)
}

/// 选中图形后可以拖的节点。
public struct FigureHandle: Equatable, Identifiable {
    public enum Role: Hashable {
        /// 顶点 / 线段端点。
        case vertex(Int)
        /// 矩形的边（拖动改一边的长度）。
        case edge(Int)
        /// 圆心、椭圆中心。
        case center
        /// 椭圆沿 angle 方向的半轴端点（拖动改长短和方向）；圆上的点（改半径）。
        case axisA
        /// 椭圆另一条半轴的端点。
        case axisB
        /// 旋转手柄。
        case rotate
        /// 立体图形的尺寸手柄（第几个）。
        case size(Int)
        /// 立体图形的旋转视角手柄。
        case orbit
    }

    public var role: Role
    public var point: CGPoint
    public var id: Role { role }
}

// MARK: - 名字和测量

extension Figure {
    /// 画布 point → 单位长度（标长度、面积时用）。
    public static let unit: CGFloat = 40

    public var name: String {
        switch self {
        case .segment: return "线段"
        case .polygon(let p): return Geo.name(of: p)
        case .ellipse(let e): return e.isCircle ? "圆" : "椭圆"
        case .solid(let s): return s.kind.name
        }
    }

    /// 选中时显示的几个量：边长、角度、面积、体积……
    public var facts: [String] {
        func len(_ v: CGFloat) -> String { Geo.format(Double(v / Figure.unit)) }
        func area(_ v: CGFloat) -> String { Geo.format(Double(v / (Figure.unit * Figure.unit))) }
        switch self {
        case .segment(let a, let b):
            return ["长度 \(len(Geo.dist(a, b)))"]
        case .polygon(let p):
            let v = p.vertices
            let s = Geo.sides(v)
            let S = abs(Geo.signedArea(v))
            switch Geo.name(of: p) {
            case "正方形": return ["边长 \(len(s[0]))", "周长 \(len(s.reduce(0, +)))", "面积 \(area(S))"]
            case "矩形": return ["长 \(len(max(s[0], s[1])))", "宽 \(len(min(s[0], s[1])))", "面积 \(area(S))"]
            case "菱形": return ["边长 \(len(s[0]))", "面积 \(area(S))"]
            default:
                if v.count == 3 {
                    let ang = Geo.angles(v)
                    let parts = v.indices.map { "∠\(p.labels[$0]) \(Int(ang[$0].rounded()))°" }
                    return parts + ["面积 \(area(S))"]
                }
                if p.rule == .regular { return ["边长 \(len(s[0]))", "面积 \(area(S))"] }
                return ["周长 \(len(s.reduce(0, +)))", "面积 \(area(S))"]
            }
        case .ellipse(let e):
            if e.isCircle {
                let r = e.a
                return ["半径 \(len(r))", "周长 \(len(2 * .pi * r))", "面积 \(area(.pi * r * r))"]
            }
            let A = max(e.a, e.b), B = min(e.a, e.b)
            let c = (A * A - B * B).squareRoot()
            return ["a = \(len(A))", "b = \(len(B))", "c = \(len(c))", "e = " + String(format: "%.2f", Double(c / A))]
        case .solid(let s):
            let d = s.dims.map { $0 / Double(Figure.unit) }
            func f(_ x: Double) -> String { Geo.format(x) }
            switch s.kind {
            case .cube:
                return ["棱长 \(f(d[0]))", "表面积 \(f(6 * d[0] * d[0]))", "体积 \(f(pow(d[0], 3)))"]
            case .cuboid:
                let (l, h, w) = (d[0], d[1], d[2])
                return ["长 \(f(l)) 宽 \(f(w)) 高 \(f(h))", "表面积 \(f(2 * (l * w + l * h + w * h)))", "体积 \(f(l * w * h))"]
            case .cylinder:
                let (r, h) = (d[0], d[1])
                return ["r = \(f(r))", "h = \(f(h))", "表面积 \(f(2 * .pi * r * (r + h)))", "体积 \(f(.pi * r * r * h))"]
            case .cone:
                let (r, h) = (d[0], d[1])
                let l = (r * r + h * h).squareRoot()
                return ["r = \(f(r))", "h = \(f(h))", "母线 \(f(l))", "体积 \(f(.pi * r * r * h / 3))"]
            case .sphere:
                let r = d[0]
                return ["R = \(f(r))", "表面积 \(f(4 * .pi * r * r))", "体积 \(f(4 * .pi * r * r * r / 3))"]
            case .prism:
                let (a, h) = (d[0], d[1])
                return ["底边 \(f(a))", "高 \(f(h))", "体积 \(f(3.0.squareRoot() / 4 * a * a * h))"]
            case .pyramid:
                let (a, h) = (d[0], d[1])
                return ["底边 \(f(a))", "高 \(f(h))", "体积 \(f(a * a * h / 3))"]
            case .tetrahedron:
                let a = d[0]
                return ["棱长 \(f(a))", "体积 \(f(pow(a, 3) / (6 * 2.0.squareRoot())))"]
            }
        }
    }

    /// 画布上占的范围（含立体图形的投影）。
    public var bounds: CGRect {
        switch self {
        case .segment(let a, let b): return Geo.bounds([a, b])
        case .polygon(let p): return Geo.bounds(p.vertices)
        case .ellipse(let e): return Geo.bounds(e.samples(48))
        case .solid(let s): return Geo.bounds(s.projection().outline)
        }
    }

    /// 能变成哪些立体图形（「变立体」菜单）。
    public var solidOptions: [Solid3.Kind] {
        switch self {
        case .polygon(let p):
            switch Geo.name(of: p) {
            case "正方形": return [.cube, .pyramid]
            case "矩形": return [.cuboid]
            default: return p.vertices.count == 3 ? [.prism, .tetrahedron] : []
            }
        case .ellipse: return [.cylinder, .cone, .sphere]
        default: return []
        }
    }

    /// 平面图形变成立体：放在原来的位置，大小对得上。
    public func extruded(_ kind: Solid3.Kind) -> Figure? {
        let c = Geo.center(of: bounds)
        switch (self, kind) {
        case (.polygon(let p), .cube), (.polygon(let p), .pyramid):
            let s = Double(Geo.sides(p.vertices).reduce(0, +) / CGFloat(p.vertices.count)) * 0.8
            return .solid(Solid3(kind: kind, center: c, dims: kind == .cube ? [s] : [s, s]))
        case (.polygon(let p), .cuboid):
            let s = Geo.sides(p.vertices)
            let w = Double(max(s[0], s[1])) * 0.8, h = Double(min(s[0], s[1])) * 0.8
            return .solid(Solid3(kind: .cuboid, center: c, dims: [w, h, min(w, h)]))
        case (.polygon(let p), .prism), (.polygon(let p), .tetrahedron):
            let a = Double(Geo.sides(p.vertices).reduce(0, +) / 3) * 0.8
            return .solid(Solid3(kind: kind, center: c, dims: kind == .prism ? [a, a * 1.2] : [a]))
        case (.ellipse(let e), _):
            let r = Double(max(e.a, e.b)) * 0.85
            switch kind {
            case .sphere: return .solid(Solid3(kind: .sphere, center: c, dims: [r]))
            case .cylinder, .cone: return .solid(Solid3(kind: kind, center: c, dims: [r * 0.8, r * 1.8]))
            default: return nil
            }
        default:
            return nil
        }
    }
}

// MARK: - 节点和拖动

extension Figure {
    /// 选中时显示的节点。
    public var handles: [FigureHandle] {
        switch self {
        case .segment(let a, let b):
            return [FigureHandle(role: .vertex(0), point: a), FigureHandle(role: .vertex(1), point: b)]
        case .polygon(let p):
            var out = p.vertices.enumerated().map { FigureHandle(role: .vertex($0.offset), point: $0.element) }
            if p.rule == .rectangle {
                for i in 0..<4 { out.append(FigureHandle(role: .edge(i), point: Geo.mid(p.vertices[i], p.vertices[(i + 1) % 4]))) }
            }
            out.append(FigureHandle(role: .rotate, point: rotateHandle(p)))
            return out
        case .ellipse(let e):
            var out = [FigureHandle(role: .center, point: e.center), FigureHandle(role: .axisA, point: e.point(at: 0))]
            if !e.isCircle { out.append(FigureHandle(role: .axisB, point: e.point(at: .pi / 2))) }
            return out
        case .solid(let s):
            // 投影后和基准点挤在一起的（俯视时的高）不显示；编号仍按完整的列表，拖动时对得上
            var out = s.sizeHandles().enumerated()
                .filter { Geo.dist($0.element.point, $0.element.anchor) > 14 }
                .map { FigureHandle(role: .size($0.offset), point: $0.element.point) }
            out.append(FigureHandle(role: .orbit, point: s.orbitHandle()))
            return out
        }
    }

    private func rotateHandle(_ p: Polygon2) -> CGPoint {
        let c = p.centroid
        let r = p.vertices.map { Geo.dist($0, c) }.max() ?? 0
        let up = CGPoint(x: sin(p.orientation), y: -cos(p.orientation))
        return CGPoint(x: c.x + up.x * (r + 30), y: c.y + up.y * (r + 30))
    }

    /// 平移整个图形。
    public func translated(by d: CGSize) -> Figure {
        func t(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x + d.width, y: p.y + d.height) }
        switch self {
        case .segment(let a, let b): return .segment(t(a), t(b))
        case .polygon(var p):
            p.vertices = p.vertices.map(t)
            return .polygon(p)
        case .ellipse(var e):
            e.center = t(e.center)
            return .ellipse(e)
        case .solid(var s):
            s.center = t(s.center)
            return .solid(s)
        }
    }

    /// 从拖动开始时的样子（self）出发，把节点 role 拖到 p 之后的样子。
    public func dragging(_ role: FigureHandle.Role, to p: CGPoint) -> Figure {
        switch self {
        case .segment(let a, let b):
            guard case .vertex(let i) = role else { return self }
            let fixed = i == 0 ? b : a
            let q = Geo.snapDirection(from: fixed, to: p)
            return i == 0 ? .segment(q, b) : .segment(a, q)
        case .polygon(let poly):
            return .polygon(dragPolygon(poly, role, p))
        case .ellipse(var e):
            switch role {
            case .center:
                e.center = p
            case .axisA:
                let d = CGPoint(x: p.x - e.center.x, y: p.y - e.center.y)
                let r = max(hypot(d.x, d.y), 8)
                if e.isCircle {
                    e.a = r
                    e.b = r
                } else {
                    e.a = r
                    e.angle = Geo.snapAngle(atan2(d.y, d.x), step: .pi / 2, within: 0.05)
                }
            case .axisB:
                let d = CGPoint(x: p.x - e.center.x, y: p.y - e.center.y)
                e.b = max(abs(d.x * e.v.x + d.y * e.v.y), 8)
            default:
                break
            }
            return .ellipse(e)
        case .solid(let s):
            return .solid(s.dragging(role, to: p))
        }
    }

    private func dragPolygon(_ start: Polygon2, _ role: FigureHandle.Role, _ p: CGPoint) -> Polygon2 {
        var poly = start
        var v = start.vertices
        let n = v.count
        switch role {
        case .rotate:
            let c = start.centroid
            let h = rotateHandle(start)
            var delta = atan2(p.y - c.y, p.x - c.x) - atan2(h.y - c.y, h.x - c.x)
            // 转到整 15° 附近时吸住
            let target = Geo.snapAngle(start.orientation + delta, step: .pi / 12, within: 0.06)
            delta = target - start.orientation
            poly.vertices = v.map { Geo.rotate($0, about: c, by: delta) }
            poly.orientation = target
            return poly
        case .edge(let k) where start.rule == .rectangle && n == 4:
            let a = v[k], b = v[(k + 1) % 4], c = v[(k + 2) % 4], d = v[(k + 3) % 4]
            let mid = Geo.mid(a, b), opp = Geo.mid(c, d)
            let len = Geo.dist(mid, opp)
            guard len > 0 else { return start }
            let nrm = CGPoint(x: (mid.x - opp.x) / len, y: (mid.y - opp.y) / len)
            var t = (p.x - mid.x) * nrm.x + (p.y - mid.y) * nrm.y
            t = max(t, 12 - len)
            v[k] = CGPoint(x: a.x + t * nrm.x, y: a.y + t * nrm.y)
            v[(k + 1) % 4] = CGPoint(x: b.x + t * nrm.x, y: b.y + t * nrm.y)
            poly.vertices = v
            return poly
        case .vertex(let i):
            switch start.rule {
            case .free:
                v[i] = p
            case .square, .rectangle:
                guard n == 4 else { v[i] = p; break }
                let j = (i + 2) % 4
                let q = v[j]
                let u = Geo.unit(CGPoint(x: v[1].x - v[0].x, y: v[1].y - v[0].y))
                let w = Geo.unit(CGPoint(x: v[3].x - v[0].x, y: v[3].y - v[0].y))
                let s0 = CGPoint(x: v[i].x - q.x, y: v[i].y - q.y)
                let su: CGFloat = (s0.x * u.x + s0.y * u.y) >= 0 ? 1 : -1
                let sw: CGFloat = (s0.x * w.x + s0.y * w.y) >= 0 ? 1 : -1
                let d = CGPoint(x: p.x - q.x, y: p.y - q.y)
                var du = (d.x * u.x + d.y * u.y) * su, dw = (d.x * w.x + d.y * w.y) * sw
                if start.rule == .square {
                    let s = max((du + dw) / 2, 12)
                    du = s
                    dw = s
                }
                du = max(du, 12)
                dw = max(dw, 12)
                let alongU = CGPoint(x: q.x + du * su * u.x, y: q.y + du * su * u.y)
                let alongW = CGPoint(x: q.x + dw * sw * w.x, y: q.y + dw * sw * w.y)
                v[i] = CGPoint(x: alongU.x + dw * sw * w.x, y: alongU.y + dw * sw * w.y)
                for k in [(i + 1) % 4, (i + 3) % 4] {
                    let sk = CGPoint(x: start.vertices[k].x - q.x, y: start.vertices[k].y - q.y)
                    v[k] = abs(sk.x * u.x + sk.y * u.y) > abs(sk.x * w.x + sk.y * w.y) ? alongU : alongW
                }
            case .regular:
                let c = start.centroid
                let r0 = Geo.dist(v[i], c)
                guard r0 > 0 else { break }
                let scale = max(Geo.dist(p, c), 12) / r0
                let delta = atan2(p.y - c.y, p.x - c.x) - atan2(v[i].y - c.y, v[i].x - c.x)
                v = v.map { q in
                    let r = Geo.rotate(q, about: c, by: delta)
                    return CGPoint(x: c.x + (r.x - c.x) * scale, y: c.y + (r.y - c.y) * scale)
                }
                poly.orientation = start.orientation + delta
            case .parallelogram, .rhombus:
                guard n == 4 else { v[i] = p; break }
                let j = (i + 2) % 4
                let q = v[j]
                let o = Geo.mid(p, q)
                var h = CGPoint(x: (v[(i + 1) % 4].x - v[(i + 3) % 4].x) / 2, y: (v[(i + 1) % 4].y - v[(i + 3) % 4].y) / 2)
                if start.rule == .rhombus {
                    let len = hypot(h.x, h.y)
                    let dir = Geo.unit(CGPoint(x: p.x - q.x, y: p.y - q.y))
                    var perp = CGPoint(x: -dir.y * len, y: dir.x * len)
                    if perp.x * h.x + perp.y * h.y < 0 { perp = CGPoint(x: -perp.x, y: -perp.y) }
                    h = perp
                }
                v[i] = p
                v[(i + 1) % 4] = CGPoint(x: o.x + h.x, y: o.y + h.y)
                v[(i + 3) % 4] = CGPoint(x: o.x - h.x, y: o.y - h.y)
            }
            // 拖得太扁、翻过去：不收
            if abs(Geo.signedArea(v)) < 60 || Geo.signedArea(v) < 0 && start.rule != .free { return start }
            poly.vertices = v
            if start.rule == .square || start.rule == .rectangle {
                poly.orientation = atan2(v[1].y - v[0].y, v[1].x - v[0].x)
            }
            return poly
        default:
            return start
        }
    }
}

// MARK: - 立体图形：网格、投影、节点

/// 投影到画布上的立体图形：看得见的面（带明暗）、棱（看不见的画虚线）、顶点字母。
public struct SolidProjection {
    public struct Edge: Equatable {
        public var a: CGPoint
        public var b: CGPoint
        public var visible: Bool
    }

    public struct Face: Equatable {
        public var points: [CGPoint]
        /// 0…1，越大越亮。
        public var light: Double
    }

    public struct Label: Equatable {
        public var point: CGPoint
        public var text: String
        /// 字放在点的哪一侧（单位向量，画布方向）。
        public var direction: CGPoint
        /// 画一个小圆点（圆心、球心）。
        public var dot: Bool
    }

    public var faces: [Face] = []
    public var edges: [Edge] = []
    public var labels: [Label] = []
    /// 投影的外轮廓（凸包），点选和选中框用。
    public var outline: [CGPoint] = []
    /// 球：轮廓是圆。
    public var circle: (center: CGPoint, radius: CGFloat)?
}

extension SolidProjection: Equatable {
    public static func == (l: SolidProjection, r: SolidProjection) -> Bool {
        l.faces == r.faces && l.edges == r.edges && l.labels == r.labels && l.outline == r.outline
            && l.circle?.center == r.circle?.center && l.circle?.radius == r.circle?.radius
    }
}

struct Mesh {
    var vertices: [Vec3] = []
    var faces: [[Int]] = []
    /// 同一个光滑曲面（圆柱、圆锥的侧面）的面编号相同：它们之间的棱不画，只画轮廓线。
    var smooth: [Int?] = []
    var labels: [(Int, String)] = []
    /// 额外的线（轴、高），按「在里面」画虚线。
    var inner: [(Vec3, Vec3)] = []
    /// 画圆点的特殊点（圆心）。
    var dots: [(Vec3, String)] = []
}

extension Solid3 {
    static let roundSegments = 48
    /// 正三角形底面三个顶点的角度：A 左前、B 右前、C 在后面（7π/6、11π/6、π/2）。
    static let triangleAngles: [Double] = [Double.pi * 7 / 6, Double.pi * 11 / 6, Double.pi / 2]

    func mesh() -> Mesh {
        var m = Mesh()
        func face(_ f: [Int], smooth: Int? = nil) {
            m.faces.append(f)
            m.smooth.append(smooth)
        }
        switch kind {
        case .cube, .cuboid:
            let (w, h, d) = kind == .cube ? (dims[0], dims[0], dims[0]) : (dims[0], dims[1], dims[2])
            let x = w / 2, y = h / 2, z = d / 2
            // A 左前下、B 右前下、C 右后下、D 左后下；A₁…在上面
            m.vertices = [Vec3(-x, -y, z), Vec3(x, -y, z), Vec3(x, -y, -z), Vec3(-x, -y, -z),
                          Vec3(-x, y, z), Vec3(x, y, z), Vec3(x, y, -z), Vec3(-x, y, -z)]
            for f in [[0, 1, 2, 3], [4, 5, 6, 7], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]] { face(f) }
            m.labels = [(0, "A"), (1, "B"), (2, "C"), (3, "D"), (4, "A₁"), (5, "B₁"), (6, "C₁"), (7, "D₁")]
        case .prism:
            let a = dims[0], h = dims[1]
            let r = a / 3.0.squareRoot()
            for y in [-h / 2, h / 2] {
                for t in Solid3.triangleAngles { m.vertices.append(Vec3(r * cos(t), y, r * sin(t))) }
            }
            for f in [[0, 1, 2], [3, 4, 5], [0, 1, 4, 3], [1, 2, 5, 4], [2, 0, 3, 5]] { face(f) }
            m.labels = [(0, "A"), (1, "B"), (2, "C"), (3, "A₁"), (4, "B₁"), (5, "C₁")]
        case .pyramid:
            let a = dims[0] / 2, h = dims[1]
            m.vertices = [Vec3(-a, -h / 2, a), Vec3(a, -h / 2, a), Vec3(a, -h / 2, -a), Vec3(-a, -h / 2, -a), Vec3(0, h / 2, 0)]
            for f in [[0, 1, 2, 3], [0, 1, 4], [1, 2, 4], [2, 3, 4], [3, 0, 4]] { face(f) }
            m.labels = [(0, "A"), (1, "B"), (2, "C"), (3, "D"), (4, "P")]
            m.inner = [(Vec3(0, h / 2, 0), Vec3(0, -h / 2, 0))]
            m.dots = [(Vec3(0, -h / 2, 0), "O")]
        case .tetrahedron:
            let a = dims[0]
            let r = a / 3.0.squareRoot(), H = a * (2.0 / 3).squareRoot()
            for t in Solid3.triangleAngles { m.vertices.append(Vec3(r * cos(t), -H / 4, r * sin(t))) }
            m.vertices.append(Vec3(0, 3 * H / 4, 0))
            for f in [[0, 1, 2], [0, 1, 3], [1, 2, 3], [2, 0, 3]] { face(f) }
            m.labels = [(0, "A"), (1, "B"), (2, "C"), (3, "P")]
        case .cylinder, .cone:
            let r = dims[0], h = dims[1]
            let n = Solid3.roundSegments
            for i in 0..<n {
                let t = Double(i) / Double(n) * 2 * .pi
                m.vertices.append(Vec3(r * cos(t), -h / 2, r * sin(t)))
            }
            if kind == .cylinder {
                for i in 0..<n {
                    let t = Double(i) / Double(n) * 2 * .pi
                    m.vertices.append(Vec3(r * cos(t), h / 2, r * sin(t)))
                }
                face(Array(0..<n))
                face(Array(n..<(2 * n)))
                for i in 0..<n { face([i, (i + 1) % n, n + (i + 1) % n, n + i], smooth: 1) }
                m.inner = [(Vec3(0, -h / 2, 0), Vec3(0, h / 2, 0))]
                m.dots = [(Vec3(0, -h / 2, 0), "O"), (Vec3(0, h / 2, 0), "O₁")]
            } else {
                m.vertices.append(Vec3(0, h / 2, 0))
                face(Array(0..<n))
                for i in 0..<n { face([i, (i + 1) % n, n], smooth: 1) }
                m.labels = [(n, "P")]
                m.inner = [(Vec3(0, h / 2, 0), Vec3(0, -h / 2, 0))]
                m.dots = [(Vec3(0, -h / 2, 0), "O")]
            }
        case .sphere:
            break
        }
        return m
    }

    /// 先绕竖直轴转 yaw，再俯仰 pitch；z 朝向看的人。
    func rotate(_ v: Vec3) -> Vec3 {
        let x1 = v.x * cos(yaw) + v.z * sin(yaw)
        let z1 = -v.x * sin(yaw) + v.z * cos(yaw)
        let y2 = v.y * cos(pitch) - z1 * sin(pitch)
        let z2 = v.y * sin(pitch) + z1 * cos(pitch)
        return Vec3(x1, y2, z2)
    }

    func screen(_ v: Vec3) -> CGPoint {
        let r = rotate(v)
        return CGPoint(x: center.x + CGFloat(r.x), y: center.y - CGFloat(r.y))
    }

    /// 正交投影：看得见的面、棱（看不见的为虚线）、字母。
    public func projection() -> SolidProjection {
        var out = SolidProjection()
        let light = Vec3(-0.45, 0.75, 0.55).normalized
        if kind == .sphere {
            let r = dims[0]
            out.circle = (center, CGFloat(r))
            out.outline = (0..<48).map { (i: Int) -> CGPoint in
                let t: Double = Double(i) / 48 * 2 * Double.pi
                let dx = CGFloat(r * cos(t)), dy = CGFloat(r * sin(t))
                return CGPoint(x: center.x + dx, y: center.y + dy)
            }
            // 赤道：前半圈实线、后半圈虚线
            let n = 72
            for i in 0..<n {
                let t0 = Double(i) / Double(n) * 2 * .pi, t1 = Double(i + 1) / Double(n) * 2 * .pi
                let p0 = Vec3(r * cos(t0), 0, r * sin(t0)), p1 = Vec3(r * cos(t1), 0, r * sin(t1))
                let front = rotate(p0 + p1).z >= 0
                out.edges.append(.init(a: screen(p0), b: screen(p1), visible: front))
            }
            // 半径：从球心指向赤道上右前方的一点
            let phi = yaw + 0.6
            let rim = Vec3(r * cos(phi), 0, r * sin(phi))
            out.edges.append(.init(a: center, b: screen(rim), visible: false))
            out.labels = [.init(point: center, text: "O", direction: CGPoint(x: -0.7, y: 0.7), dot: true)]
            out.faces = [.init(points: out.outline, light: 0.8)]
            return out
        }
        let m = mesh()
        let centroid = m.vertices.reduce(Vec3(0, 0, 0), +) * (1 / Double(max(m.vertices.count, 1)))
        // 每个面朝外的法向（转好之后）
        var normals: [Vec3] = []
        for f in m.faces {
            let a = m.vertices[f[0]], b = m.vertices[f[1]], c = m.vertices[f[2]]
            var nrm = (b - a).cross(c - a).normalized
            let fc = f.map { m.vertices[$0] }.reduce(Vec3(0, 0, 0), +) * (1 / Double(f.count))
            if nrm.dot(fc - centroid) < 0 { nrm = nrm * -1 }
            normals.append(rotate(nrm))
        }
        let visible = normals.map { $0.z > 1e-6 }
        for (i, f) in m.faces.enumerated() where visible[i] {
            let l = 0.5 + 0.5 * max(0, normals[i].dot(light))
            out.faces.append(.init(points: f.map { screen(m.vertices[$0]) }, light: l))
        }
        // 棱：两个相邻面里有一个看得见就是实线；光滑曲面内部的棱只在轮廓处画
        var adjacency: [String: [Int]] = [:]
        var endpoints: [String: (Int, Int)] = [:]
        for (fi, f) in m.faces.enumerated() {
            for k in 0..<f.count {
                let a = f[k], b = f[(k + 1) % f.count]
                let key = a < b ? "\(a)-\(b)" : "\(b)-\(a)"
                adjacency[key, default: []].append(fi)
                endpoints[key] = (min(a, b), max(a, b))
            }
        }
        for key in adjacency.keys.sorted() {
            let fs = adjacency[key]!, (a, b) = endpoints[key]!
            let anyVisible = fs.contains { visible[$0] }
            if fs.count == 2, let g = m.smooth[fs[0]], g == m.smooth[fs[1]] {
                // 光滑面内部：只有一边看得见时是轮廓线
                guard visible[fs[0]] != visible[fs[1]] else { continue }
            }
            out.edges.append(.init(a: screen(m.vertices[a]), b: screen(m.vertices[b]), visible: anyVisible))
        }
        for (a, b) in m.inner {
            out.edges.append(.init(a: screen(a), b: screen(b), visible: false))
        }
        let c2 = screen(centroid)
        for (i, text) in m.labels {
            let p = screen(m.vertices[i])
            out.labels.append(.init(point: p, text: text, direction: Geo.unit(CGPoint(x: p.x - c2.x, y: p.y - c2.y)), dot: false))
        }
        for (v, text) in m.dots {
            out.labels.append(.init(point: screen(v), text: text, direction: CGPoint(x: 0.8, y: 0.6), dot: true))
        }
        out.outline = Geo.convexHull(m.vertices.map(screen))
        return out
    }

    /// 尺寸手柄：拖动点、按哪个点量远近、改哪几项尺寸。
    struct SizeHandle {
        var point: CGPoint
        var anchor: CGPoint
        var dims: [Int]
    }

    func sizeHandles() -> [SizeHandle] {
        var out: [SizeHandle] = []
        func axisHandle(_ axis: Vec3, _ half: Double, _ dim: Int) {
            // 朝向看的人的那一面
            let dir = rotate(axis).z >= 0 ? axis : axis * -1
            let p = screen(dir * half)
            guard Geo.dist(p, center) > 14 else { return }
            out.append(SizeHandle(point: p, anchor: center, dims: [dim]))
        }
        switch kind {
        case .cube:
            let m = mesh()
            let corner = m.vertices.max { a, b in
                let pa = screen(a), pb = screen(b)
                return pa.x - pa.y < pb.x - pb.y
            }!
            out.append(SizeHandle(point: screen(corner), anchor: center, dims: [0]))
        case .cuboid:
            axisHandle(Vec3(1, 0, 0), dims[0] / 2, 0)
            axisHandle(Vec3(0, 1, 0), dims[1] / 2, 1)
            axisHandle(Vec3(0, 0, 1), dims[2] / 2, 2)
        case .cylinder, .cone, .pyramid, .prism:
            let h = dims[1]
            let topY = kind == .cylinder || kind == .prism ? h / 2 : -h / 2
            let ringCenter = Vec3(0, topY, 0)
            // 底面（圆柱、棱柱用顶面）上投影最靠右的一点：改半径 / 边长
            let r = kind == .pyramid ? dims[0] / 2 : kind == .prism ? dims[0] / 3.0.squareRoot() : dims[0]
            var best = Vec3(r, topY, 0)
            if kind == .pyramid {
                best = [Vec3(-r, topY, r), Vec3(r, topY, r), Vec3(r, topY, -r), Vec3(-r, topY, -r)].max { screen($0).x < screen($1).x }!
            } else if kind == .prism {
                best = mesh().vertices[3...5].max { screen($0).x < screen($1).x }!
            } else {
                for i in 0..<36 {
                    let t = Double(i) / 36 * 2 * .pi
                    let q = Vec3(r * cos(t), topY, r * sin(t))
                    if screen(q).x > screen(best).x { best = q }
                }
            }
            out.append(SizeHandle(point: screen(best), anchor: screen(ringCenter), dims: [0]))
            // 高：顶点（锥）或顶面中心（柱）
            let apex = Vec3(0, h / 2, 0)
            out.append(SizeHandle(point: screen(apex), anchor: center, dims: [1]))
        case .sphere:
            out.append(SizeHandle(point: CGPoint(x: center.x + CGFloat(dims[0]), y: center.y), anchor: center, dims: [0]))
        case .tetrahedron:
            out.append(SizeHandle(point: screen(mesh().vertices[3]), anchor: center, dims: [0]))
        }
        return out
    }

    func orbitHandle() -> CGPoint {
        let b = Geo.bounds(projection().outline)
        return CGPoint(x: b.midX, y: b.maxY + 34)
    }

    func dragging(_ role: FigureHandle.Role, to p: CGPoint) -> Solid3 {
        var s = self
        switch role {
        case .orbit:
            let h = orbitHandle()
            s.yaw = yaw + Double(p.x - h.x) * 0.012
            s.pitch = min(max(pitch + Double(p.y - h.y) * 0.012, -1.5), 1.5)
        case .size(let i):
            let specs = sizeHandles()
            guard specs.indices.contains(i) else { return self }
            let spec = specs[i]
            let d0 = CGPoint(x: spec.point.x - spec.anchor.x, y: spec.point.y - spec.anchor.y)
            let len2 = d0.x * d0.x + d0.y * d0.y
            guard len2 > 1 else { return self }
            let ratio = Double(((p.x - spec.anchor.x) * d0.x + (p.y - spec.anchor.y) * d0.y) / len2)
            let dimsToScale = [.cube, .sphere, .tetrahedron].contains(kind) ? Array(dims.indices) : spec.dims
            for k in dimsToScale { s.dims[k] = max(dims[k] * ratio, 16) }
        default:
            break
        }
        return s
    }

    /// 三视图：主视（从前往后看）、左视（从左往右看）、俯视（从上往下看）、斜着看。
    public enum View: String, CaseIterable {
        case front, side, top, oblique

        public var name: String {
            switch self {
            case .front: return "主视"
            case .side: return "左视"
            case .top: return "俯视"
            case .oblique: return "立体"
            }
        }
    }

    public func viewed(_ v: View) -> Solid3 {
        var s = self
        switch v {
        case .front: (s.yaw, s.pitch) = (0, 0)
        case .side: (s.yaw, s.pitch) = (.pi / 2, 0)
        case .top: (s.yaw, s.pitch) = (0, .pi / 2)
        case .oblique: (s.yaw, s.pitch) = (Solid3.defaultYaw, Solid3.defaultPitch)
        }
        return s
    }
}

// MARK: - 平面几何小工具

enum Geo {
    static func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
    static func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }

    static func mean(_ pts: [CGPoint]) -> CGPoint {
        guard !pts.isEmpty else { return .zero }
        var x: CGFloat = 0, y: CGFloat = 0
        for p in pts { x += p.x; y += p.y }
        return CGPoint(x: x / CGFloat(pts.count), y: y / CGFloat(pts.count))
    }

    static func unit(_ v: CGPoint) -> CGPoint {
        let l = hypot(v.x, v.y)
        return l > 0 ? CGPoint(x: v.x / l, y: v.y / l) : CGPoint(x: 1, y: 0)
    }

    static func rotate(_ p: CGPoint, about c: CGPoint, by a: CGFloat) -> CGPoint {
        let dx = p.x - c.x, dy = p.y - c.y
        return CGPoint(x: c.x + dx * cos(a) - dy * sin(a), y: c.y + dx * sin(a) + dy * cos(a))
    }

    static func bounds(_ pts: [CGPoint]) -> CGRect {
        guard let f = pts.first else { return .null }
        var minX = f.x, maxX = f.x, minY = f.y, maxY = f.y
        for p in pts {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    static func center(of r: CGRect) -> CGPoint { CGPoint(x: r.midX, y: r.midY) }

    /// 有向面积：画布上（y 向下）顺时针为正。
    static func signedArea(_ v: [CGPoint]) -> CGFloat {
        guard v.count >= 3 else { return 0 }
        var s: CGFloat = 0
        for i in 0..<v.count {
            let a = v[i], b = v[(i + 1) % v.count]
            s += a.x * b.y - b.x * a.y
        }
        return s / 2
    }

    static func sides(_ v: [CGPoint]) -> [CGFloat] {
        v.indices.map { dist(v[$0], v[($0 + 1) % v.count]) }
    }

    /// 每个顶点处的内角（度）。
    static func angles(_ v: [CGPoint]) -> [Double] {
        v.indices.map { (i: Int) -> Double in
            let p = v[(i - 1 + v.count) % v.count], q = v[i], r = v[(i + 1) % v.count]
            let a = atan2(p.y - q.y, p.x - q.x), b = atan2(r.y - q.y, r.x - q.x)
            var d = abs(Double(a - b)) * 180 / .pi
            if d > 180 { d = 360 - d }
            return d
        }
    }

    /// 两条边方向差（度，0…90）。
    static func directionGap(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> Double {
        let t1 = atan2(b.y - a.y, b.x - a.x), t2 = atan2(d.y - c.y, d.x - c.x)
        var g = abs(Double(t1 - t2)).truncatingRemainder(dividingBy: .pi) * 180 / .pi
        if g > 90 { g = 180 - g }
        return g
    }

    /// 现在的样子叫什么（拖动时跟着变）。
    static func name(of p: Polygon2) -> String {
        let v = p.vertices
        switch p.rule {
        case .square: return "正方形"
        case .rectangle: return "矩形"
        case .rhombus: return "菱形"
        case .parallelogram: return "平行四边形"
        case .regular: return v.count == 3 ? "等边三角形" : "正\(chineseNumber(v.count))边形"
        case .free: break
        }
        let s = sides(v), ang = angles(v)
        func eq(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) <= 0.025 * max(a, b) }
        switch v.count {
        case 3:
            let right = ang.contains { abs($0 - 90) < 1.5 }
            let equal = (0..<3).filter { eq(s[$0], s[($0 + 1) % 3]) }.count
            if equal >= 3 { return "等边三角形" }
            if right { return equal >= 1 ? "等腰直角三角形" : "直角三角形" }
            if equal >= 1 { return "等腰三角形" }
            return ang.contains { $0 > 90 } ? "钝角三角形" : "锐角三角形"
        case 4:
            let allRight = ang.allSatisfy { abs($0 - 90) < 1.5 }
            let allEqual = eq(s[0], s[1]) && eq(s[1], s[2]) && eq(s[2], s[3])
            let par02 = directionGap(v[0], v[1], v[2], v[3]) < 1.5, par13 = directionGap(v[1], v[2], v[3], v[0]) < 1.5
            if allRight { return allEqual ? "正方形" : "矩形" }
            if par02 && par13 { return allEqual ? "菱形" : "平行四边形" }
            if par02 || par13 {
                let legsEqual = par02 ? eq(s[1], s[3]) : eq(s[0], s[2])
                if ang.contains(where: { abs($0 - 90) < 1.5 }) { return "直角梯形" }
                return legsEqual ? "等腰梯形" : "梯形"
            }
            return "四边形"
        default:
            return "\(chineseNumber(v.count))边形"
        }
    }

    static func chineseNumber(_ n: Int) -> String {
        let d = ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]
        return n <= 10 ? d[n] : String(n)
    }

    static func format(_ x: Double) -> String {
        if abs(x - x.rounded()) < 0.05 { return String(Int(x.rounded())) }
        return String(format: "%.1f", x)
    }

    /// 接近整 step 的角度吸过去（弧度）。
    static func snapAngle(_ a: CGFloat, step: CGFloat, within tol: CGFloat) -> CGFloat {
        let k = (a / step).rounded()
        return abs(a - k * step) < tol ? k * step : a
    }

    /// 线段接近水平 / 竖直时吸过去。
    static func snapDirection(from a: CGPoint, to b: CGPoint) -> CGPoint {
        let d = dist(a, b)
        let t = snapAngle(atan2(b.y - a.y, b.x - a.x), step: .pi / 2, within: 0.04)
        return CGPoint(x: a.x + d * cos(t), y: a.y + d * sin(t))
    }

    /// 凸包（Andrew 单调链），顺时针。
    static func convexHull(_ pts: [CGPoint]) -> [CGPoint] {
        let p = pts.sorted { $0.x != $1.x ? $0.x < $1.x : $0.y < $1.y }
        guard p.count > 2 else { return p }
        func cross(_ o: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat { (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x) }
        var lower: [CGPoint] = [], upper: [CGPoint] = []
        for q in p {
            while lower.count >= 2 && cross(lower[lower.count - 2], lower[lower.count - 1], q) <= 0 { lower.removeLast() }
            lower.append(q)
        }
        for q in p.reversed() {
            while upper.count >= 2 && cross(upper[upper.count - 2], upper[upper.count - 1], q) <= 0 { upper.removeLast() }
            upper.append(q)
        }
        return Array(lower.dropLast() + upper.dropLast())
    }

    /// 点在多边形里（射线法）。
    static func contains(_ poly: [CGPoint], _ p: CGPoint) -> Bool {
        var inside = false
        var j = poly.count - 1
        for i in 0..<poly.count {
            let a = poly[i], b = poly[j]
            if (a.y > p.y) != (b.y > p.y), p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
            j = i
        }
        return inside
    }
}

extension Figure {
    /// 点 p 落在图形上（线附近 tol 以内，或者封闭图形的内部）。
    public func hitTest(_ p: CGPoint, tolerance tol: CGFloat = 16, interior: Bool = true) -> Bool {
        func nearSegment(_ a: CGPoint, _ b: CGPoint) -> Bool {
            let l2 = (b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y)
            guard l2 > 0 else { return Geo.dist(p, a) < tol }
            let t = max(0, min(1, ((p.x - a.x) * (b.x - a.x) + (p.y - a.y) * (b.y - a.y)) / l2))
            return Geo.dist(p, CGPoint(x: a.x + t * (b.x - a.x), y: a.y + t * (b.y - a.y))) < tol
        }
        switch self {
        case .segment(let a, let b):
            return nearSegment(a, b)
        case .polygon(let poly):
            let v = poly.vertices
            if interior, Geo.contains(v, p) { return true }
            return v.indices.contains { nearSegment(v[$0], v[($0 + 1) % v.count]) }
        case .ellipse(let e):
            let d = CGPoint(x: p.x - e.center.x, y: p.y - e.center.y)
            let x = (d.x * e.u.x + d.y * e.u.y) / max(e.a, 1), y = (d.x * e.v.x + d.y * e.v.y) / max(e.b, 1)
            let r = (x * x + y * y).squareRoot()
            if interior, r <= 1 { return true }
            return abs(r - 1) * min(e.a, e.b) < tol
        case .solid(let s):
            let outline = s.projection().outline
            return Geo.contains(outline, p) || outline.indices.contains { nearSegment(outline[$0], outline[($0 + 1) % outline.count]) }
        }
    }
}
