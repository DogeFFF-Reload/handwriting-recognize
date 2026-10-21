import Foundation

/// 平面上的线性变换 (x, y) ↦ (a·x + b·y, c·x + d·y)，也就是矩阵 \begin{pmatrix}a&b\\c&d\end{pmatrix}：
/// 第一列 (a, c) 是 î 变到哪，第二列 (b, d) 是 ĵ 变到哪。「看变换」的卡片拖基向量、做逆变换都用它。
public struct LinearMap2: Equatable, Codable {
    public var a: Double
    public var b: Double
    public var c: Double
    public var d: Double

    public init(a: Double, b: Double, c: Double, d: Double) {
        self.a = a
        self.b = b
        self.c = c
        self.d = d
    }

    public static let identity = LinearMap2(a: 1, b: 0, c: 0, d: 1)

    /// î 变成的向量（第一列）。
    public var i: (x: Double, y: Double) { (a, c) }
    /// ĵ 变成的向量（第二列）。
    public var j: (x: Double, y: Double) { (b, d) }

    /// 单位方格变成的平行四边形面积是原来的 |det| 倍；det < 0 时方向翻转。
    public var determinant: Double { a * d - b * c }

    public var isInvertible: Bool { abs(determinant) > 1e-9 }

    /// 逆变换：A⁻¹ = \frac{1}{ad − bc}\begin{pmatrix}d&−b\\−c&a\end{pmatrix}。det = 0 时没有。
    public var inverse: LinearMap2? {
        let det = determinant
        guard abs(det) > 1e-9 else { return nil }
        return LinearMap2(a: d / det, b: -b / det, c: -c / det, d: a / det)
    }

    public func apply(_ x: Double, _ y: Double) -> (x: Double, y: Double) {
        (a * x + b * y, c * x + d * y)
    }

    /// 先做自己、再做 next：矩阵乘积 next · self。
    public func then(_ next: LinearMap2) -> LinearMap2 {
        LinearMap2(a: next.a * a + next.b * c, b: next.a * b + next.b * d,
                   c: next.c * a + next.d * c, d: next.c * b + next.d * d)
    }

    /// 逐个元素插值（动画用）：t = 0 是自己，t = 1 是 other。
    public func interpolated(to other: LinearMap2, _ t: Double) -> LinearMap2 {
        LinearMap2(a: a + (other.a - a) * t, b: b + (other.b - b) * t,
                   c: c + (other.c - c) * t, d: d + (other.d - d) * t)
    }

    /// 元素吸附到 step 的整数倍（拖基向量时落在格点上）。
    public func snapped(_ step: Double = 0.5) -> LinearMap2 {
        func s(_ v: Double) -> Double {
            let r = (v / step).rounded() * step
            return r == 0 ? 0 : r   // 不要 −0
        }
        return LinearMap2(a: s(a), b: s(b), c: s(c), d: s(d))
    }

    /// 写回式子：\begin{pmatrix}2 & 0 \\ 0 & 1\end{pmatrix}（分数写成 \frac）。
    public var latex: String {
        let f = MathExpr.formatNumber
        return "\\begin{pmatrix}\(f(a)) & \(f(b)) \\\\ \(f(c)) & \(f(d))\\end{pmatrix}"
    }

    // MARK: 说明（卡片底下的一行字）

    /// 「det = 2：面积 ×2」「det = −1：面积 ×1，方向翻转」「det = 0：面积变成 0」。
    public var areaText: String {
        let det = determinant
        guard abs(det) > 1e-9 else { return "det = 0：面积变成 0" }
        var text = "det = \(Self.plain(det))：面积 ×\(Self.plain(abs(det)))"
        if det < 0 { text += "，方向翻转" }
        return text
    }

    /// 是哪一种变换：伸缩、旋转、剪切、反射、压扁……认不出来就说「一般的线性变换」。
    public var kindText: String {
        func same(_ x: Double, _ y: Double) -> Bool { abs(x - y) < 1e-9 }
        let det = determinant
        if same(a, 0), same(b, 0), same(c, 0), same(d, 0) { return "所有点都压到原点" }
        if same(det, 0) { return "压成一条直线（不可逆）" }
        if same(b, 0), same(c, 0) {
            if same(a, 1), same(d, 1) { return "恒等变换：什么都不动" }
            if same(a, -1), same(d, -1) { return "关于原点对称（旋转 180°）" }
            if same(a, -1), same(d, 1) { return "关于 y 轴反射" }
            if same(a, 1), same(d, -1) { return "关于 x 轴反射" }
            if same(a, d), a > 0 { return a > 1 ? "整体放大 \(Self.plain(a)) 倍" : "整体缩小为 \(Self.plain(a)) 倍" }
            return "横向 ×\(Self.plain(a))，纵向 ×\(Self.plain(d))"
        }
        // 旋转（可以再带缩放）：a = d，b = −c
        if same(a, d), same(b, -c) {
            let r = (a * a + c * c).squareRoot()
            let angle = Self.plain(atan2(c, a) * 180 / .pi)
            return same(r, 1) ? "逆时针旋转 \(angle)°" : "逆时针旋转 \(angle)°，再放大 \(Self.plain(r)) 倍"
        }
        // 反射：a = −d，b = c，而且两列都是单位向量
        if same(a, -d), same(b, c), same(a * a + c * c, 1) {
            return "关于倾斜 \(Self.plain(atan2(c, a) * 90 / .pi))° 的直线反射"
        }
        if same(a, 1), same(d, 1), same(c, 0) { return "水平剪切：ĵ 往横向偏了 \(Self.plain(b))" }
        if same(a, 1), same(d, 1), same(b, 0) { return "竖直剪切：î 往竖向偏了 \(Self.plain(c))" }
        return det < 0 ? "一般的线性变换（方向翻转）" : "一般的线性变换"
    }

    /// 普通文字的数：整数照写，其余最多两位小数（−0.5、1.41），负号用 −。
    static func plain(_ v: Double) -> String {
        var s: String
        if abs(v - v.rounded()) < 1e-9 {
            s = String(Int(v.rounded()))
        } else {
            s = String(format: "%.2f", v)
            while s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".") { s.removeLast() }
        }
        if s == "-0" { s = "0" }
        return s.replacingOccurrences(of: "-", with: "−")
    }
}
