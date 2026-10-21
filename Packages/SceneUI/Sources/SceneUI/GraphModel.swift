import CoreGraphics
import Foundation
import Observation

// 函数卡片里的图像（GeoGebra 的「绘图区」）：要画的函数、视窗、参数、推导对了之后的标注。
// 一个函数式子一个 GraphModel。SceneUI 不依赖 InkCore：一般表达式由 App 传一个求值闭包进来。

/// 视窗：中心 + 每个 point 代表多少单位。卡片放大时多看到一些坐标，而不是把图拉伸（和 GeoGebra 一样）。
public struct GraphViewport: Equatable {
    public var centerX: Double
    public var centerY: Double
    public var unitsPerPointX: Double
    public var unitsPerPointY: Double

    public init(centerX: Double, centerY: Double, unitsPerPointX: Double, unitsPerPointY: Double) {
        self.centerX = centerX
        self.centerY = centerY
        self.unitsPerPointX = unitsPerPointX
        self.unitsPerPointY = unitsPerPointY
    }

    /// 让 [xMin, xMax] × [yMin, yMax] 正好铺满 size。
    public init(xMin: Double, xMax: Double, yMin: Double, yMax: Double, size: CGSize) {
        let w = Double(max(size.width, 1)), h = Double(max(size.height, 1))
        self.init(centerX: (xMin + xMax) / 2, centerY: (yMin + yMax) / 2,
                  unitsPerPointX: max(xMax - xMin, 1e-9) / w, unitsPerPointY: max(yMax - yMin, 1e-9) / h)
    }

    public func xRange(_ size: CGSize) -> ClosedRange<Double> {
        let half = Double(size.width) / 2 * unitsPerPointX
        return (centerX - half)...(centerX + half)
    }

    public func yRange(_ size: CGSize) -> ClosedRange<Double> {
        let half = Double(size.height) / 2 * unitsPerPointY
        return (centerY - half)...(centerY + half)
    }

    public func point(_ x: Double, _ y: Double, in size: CGSize) -> CGPoint {
        CGPoint(x: Double(size.width) / 2 + (x - centerX) / unitsPerPointX,
                y: Double(size.height) / 2 - (y - centerY) / unitsPerPointY)
    }

    public func value(at p: CGPoint, in size: CGSize) -> (x: Double, y: Double) {
        (centerX + (Double(p.x) - Double(size.width) / 2) * unitsPerPointX,
         centerY - (Double(p.y) - Double(size.height) / 2) * unitsPerPointY)
    }

    /// 拖动平移：手指往右，坐标往左走。
    public func panned(by t: CGSize) -> GraphViewport {
        var v = self
        v.centerX -= Double(t.width) * unitsPerPointX
        v.centerY += Double(t.height) * unitsPerPointY
        return v
    }

    /// 以 anchor（视图坐标）为不动点缩放；factor > 1 放大。
    public func zoomed(by factor: Double, around anchor: CGPoint, in size: CGSize) -> GraphViewport {
        let f = min(max(factor, 0.05), 20)
        let fixed = value(at: anchor, in: size)
        var v = self
        v.unitsPerPointX = min(max(unitsPerPointX / f, 1e-6), 1e6)
        v.unitsPerPointY = min(max(unitsPerPointY / f, 1e-6), 1e6)
        let moved = v.value(at: anchor, in: size)
        v.centerX += fixed.x - moved.x
        v.centerY += fixed.y - moved.y
        return v
    }
}

/// 一条参数滑条（a、b、k…）。
public struct GraphParam: Identifiable, Equatable {
    public var name: String
    public var value: Double
    public var min: Double
    public var max: Double
    public var id: String { name }

    public init(name: String, value: Double = 1, min: Double = -5, max: Double = 5) {
        self.name = name
        self.value = value
        self.min = min
        self.max = max
    }
}

/// 曲线上值得标出来的点：零点、极值点、和 y 轴的交点。
public struct GraphSpecialPoint: Equatable, Identifiable {
    public enum Kind: Equatable { case root, maximum, minimum, yIntercept }
    public var kind: Kind
    public var x: Double
    public var y: Double
    public var id: String { "\(kind)-\(Int((x * 1e4).rounded()))" }

    public var name: String {
        switch kind {
        case .root: return "零点"
        case .maximum: return "极大值"
        case .minimum: return "极小值"
        case .yIntercept: return "与 y 轴交点"
        }
    }
}

/// 「求解」标在这条函数图像上的东西：定积分涂出来的面积、极限的那个点（空心）。
public struct GraphOverlay: Equatable, Identifiable {
    public enum Kind: Equatable {
        /// ∫_a^b f(x)dx：曲线和 x 轴之间 a 到 b 这一块（a、b 可以是 ±∞）。
        case area(from: Double, to: Double)
        /// lim_{x→a} f(x) = L。
        case point(x: Double, y: Double)
    }
    /// 是哪一条求解标的（App 用那一项的 id），重算、删除时按它换掉。
    public var id: String
    public var kind: Kind
    /// 写在旁边的字：S = −16/3、极限 5。
    public var label: String

    public init(id: String, kind: Kind, label: String) {
        self.id = id
        self.kind = kind
        self.label = label
    }
}

/// 两个函数画在同一张图里时选的区间：只看这一段里的交点，涂出两条曲线之间的面积。端点可以拖。
public struct GraphRegion: Equatable {
    public var from: Double
    public var to: Double

    public init(from: Double, to: Double) {
        self.from = from
        self.to = to
    }

    public var lower: Double { min(from, to) }
    public var upper: Double { max(from, to) }

    public func contains(_ x: Double) -> Bool { x >= lower - 1e-9 && x <= upper + 1e-9 }
}

@Observable
public final class GraphModel {
    public enum Source {
        /// 纯数字系数的多项式：每个系数一条滑条（第一幕擦掉 5 写成 3，b 跟着变）。
        case polynomial([PolyTerm])
        /// 一般表达式：App 给求值闭包，x 以外的字母是参数。
        case expression((Double, [String: Double]) -> Double)
    }

    public var source: Source
    public var params: [GraphParam]
    /// 第二幕改对之后为 true：标出极值点和水平切线、画导函数、出现可拖的切点（A9）。
    public var reveal = false
    /// nil 表示按函数自动定视窗；用户一拖一缩就固定下来。
    public var viewport: GraphViewport?
    /// 可拖切点的横坐标（reveal 后出现）。
    public var probeX: Double = 1.6
    /// 每次换函数或改系数、参数 +1。
    public private(set) var revision = 0
    /// 系数滑条的范围 ±sliderSpan：按识别出来时的系数定，拖动时不跟着变，免得滑块在手指下跑。
    public private(set) var sliderSpan: Double = 5
    /// 求解标上的面积、点。
    public private(set) var overlays: [GraphOverlay] = []
    /// 别的函数画进了这张图时选的区间（没有就是 nil：只标交点）。
    public var region: GraphRegion?

    /// 换上（或加上）一条标注；新的标注落在视窗外时重新取景。
    public func setOverlay(_ o: GraphOverlay) {
        if let i = overlays.firstIndex(where: { $0.id == o.id }) {
            guard overlays[i] != o else { return }
            overlays[i] = o
        } else {
            overlays.append(o)
        }
        viewport = nil
    }

    public func removeOverlay(id: String) {
        overlays.removeAll { $0.id == id }
    }

    public init(polynomial terms: [PolyTerm]) {
        source = .polynomial(terms)
        params = []
        sliderSpan = Self.span(for: terms)
    }

    public init(parameters: [String], evaluate: @escaping (Double, [String: Double]) -> Double) {
        source = .expression(evaluate)
        params = parameters.map { GraphParam(name: $0) }
    }

    public var terms: [PolyTerm]? {
        if case .polynomial(let t) = source { return t }
        return nil
    }

    public var hasSliders: Bool { !(terms ?? []).isEmpty || !params.isEmpty }

    /// 换成另一条函数（重新识别、手动改式子）。视窗重新自动取景，reveal 不动；同名参数保留当前值。
    public func replace(with other: GraphModel) {
        source = other.source
        let old = Dictionary(uniqueKeysWithValues: params.map { ($0.name, $0) })
        params = other.params.map { old[$0.name] ?? $0 }
        sliderSpan = other.sliderSpan
        viewport = nil
        revision += 1
    }

    static func span(for terms: [PolyTerm]) -> Double {
        max(5, (terms.map { abs($0.coef) }.max() ?? 0) * 2).rounded(.up)
    }

    public func setCoefficient(_ value: Double, at index: Int) {
        guard case .polynomial(var t) = source, t.indices.contains(index) else { return }
        t[index].coef = value
        source = .polynomial(t)
        revision += 1
    }

    public func setParam(_ name: String, to value: Double) {
        guard let i = params.firstIndex(where: { $0.name == name }) else { return }
        params[i].value = value
        revision += 1
    }

    public func y(_ x: Double) -> Double {
        switch source {
        case .polynomial(let t): return Poly.eval(t, x)
        case .expression(let f):
            var env: [String: Double] = [:]
            for p in params { env[p.name] = p.value }
            return f(x, env)
        }
    }

    /// 斜率：多项式用导数，其他用中心差分。
    public func slope(_ x: Double) -> Double {
        if let t = terms { return Poly.eval(Poly.derivative(t), x) }
        let h = max(1e-5, abs(x) * 1e-6)
        return (y(x + h) - y(x - h)) / (2 * h)
    }

    // MARK: 自动取景

    /// 先找零点和极值点，横向把离原点最近的几个都框进来（sin x 这种不会缩成一团）；
    /// 纵向按极值和曲线大致的取值定，留出余量。横向至少 8 个单位宽。
    public func fittedViewport(for size: CGSize) -> GraphViewport {
        let features = specialPoints(in: -12...12, samples: 1200)
            .filter { $0.kind != .yIntercept }
            .sorted { abs($0.x) < abs($1.x) }
            .prefix(5)
        var xMin = -5.0, xMax = 5.0
        if let lo = features.map(\.x).min(), let hi = features.map(\.x).max() {
            let pad = max(1.2, (hi - lo) * 0.35)
            xMin = min(lo - pad, -1)
            xMax = max(hi + pad, 1)
            if xMax - xMin < 8 {
                let mid = (lo + hi) / 2
                xMin = mid - 4
                xMax = mid + 4
            }
        }
        // 积分区间、极限的点也要在视窗里
        for o in overlays {
            switch o.kind {
            case .area(let a, let b):
                let lo = a.isFinite ? a : (b.isFinite ? b - 6 : -6), hi = b.isFinite ? b : lo + 6
                let pad = max(0.8, (hi - lo) * 0.25)
                xMin = min(xMin, lo - pad)
                xMax = max(xMax, hi + pad)
            case .point(let x, _):
                xMin = min(xMin, x - 1.5)
                xMax = max(xMax, x + 1.5)
            }
        }
        // 两个函数同图时选的区间也要在视窗里
        if let r = region {
            let pad = max(0.8, (r.upper - r.lower) * 0.25)
            xMin = min(xMin, r.lower - pad)
            xMax = max(xMax, r.upper + pad)
        }
        // 纵向：极值的大小优先；没有极值时按曲线在中间 60% 的取值（指数函数不会把整条线压扁在 x 轴上）
        var ys: [Double] = []
        let n = 200
        for i in 0...n {
            let v = y(xMin + (xMax - xMin) * Double(i) / Double(n))
            if v.isFinite { ys.append(v) }
        }
        ys.sort()
        var yMin = -5.0, yMax = 5.0
        let extremeYs = features.filter { $0.kind == .maximum || $0.kind == .minimum }.map(\.y)
        if let m = extremeYs.map(abs).max(), m > 1e-9 {
            let r = max(m * 2.1, 2)
            yMin = -r
            yMax = r
            if extremeYs.allSatisfy({ $0 > 0 }) { yMin = -r * 0.3 }
            if extremeYs.allSatisfy({ $0 < 0 }) { yMax = r * 0.3 }
        } else if ys.count > 10 {
            let lo = ys[ys.count / 5], hi = ys[ys.count * 4 / 5]
            let span = max(hi - lo, 2)
            yMin = min(lo - span * 0.35, -1)
            yMax = max(hi + span * 0.35, 1)
        }
        // 两个方向的单位长度别差太多，否则斜线看着失真
        var v = GraphViewport(xMin: xMin, xMax: xMax, yMin: yMin, yMax: yMax, size: size)
        let ratio = v.unitsPerPointY / v.unitsPerPointX
        if ratio < 1 { v.unitsPerPointY = v.unitsPerPointX }   // y 比 x 还放大：改成等比
        if ratio > 40 { v.unitsPerPointX = v.unitsPerPointY / 40 }
        return v
    }

    // MARK: 特殊点

    /// 在 range 里找零点、极值点和 y 轴交点（取样后二分）。
    public func specialPoints(in range: ClosedRange<Double>, samples: Int = 480) -> [GraphSpecialPoint] {
        let lo = range.lowerBound, hi = range.upperBound
        guard hi > lo else { return [] }
        let step = (hi - lo) / Double(samples)
        var xs: [Double] = [], vs: [Double] = []
        for i in 0...samples {
            let x = lo + Double(i) * step
            xs.append(x)
            vs.append(y(x))
        }
        let finite = vs.filter(\.isFinite).map(abs).sorted()
        let typical = finite.isEmpty ? 1 : max(finite[finite.count / 2], 1)
        var out: [GraphSpecialPoint] = []

        // 零点：相邻两点异号，且不是渐近线两侧的跳变
        for i in 1..<xs.count {
            let a = vs[i - 1], b = vs[i]
            guard a.isFinite, b.isFinite else { continue }
            if a == 0 { out.append(.init(kind: .root, x: xs[i - 1], y: 0)); continue }
            guard a * b < 0, abs(a - b) < typical * 20 else { continue }
            var l = xs[i - 1], r = xs[i]
            for _ in 0..<50 {
                let m = (l + r) / 2
                if (y(l) < 0) == (y(m) < 0) { l = m } else { r = m }
            }
            out.append(.init(kind: .root, x: (l + r) / 2, y: 0))
        }
        // 极值：多项式用导数精确求；其他按取样找局部最高 / 最低，再用三分法收紧
        if let t = terms {
            for e in Poly.extrema(t, lo: lo, hi: hi) {
                out.append(.init(kind: e.kind == .max ? .maximum : .minimum, x: e.x, y: e.y))
            }
        } else {
            for i in 1..<(xs.count - 1) {
                let a = vs[i - 1], b = vs[i], c = vs[i + 1]
                guard a.isFinite, b.isFinite, c.isFinite else { continue }
                let isMax = b > a && b >= c, isMin = b < a && b <= c
                guard isMax || isMin, abs(b) < typical * 50 else { continue }
                var l = xs[i - 1], r = xs[i + 1]
                for _ in 0..<60 {
                    let m1 = l + (r - l) / 3, m2 = r - (r - l) / 3
                    if (y(m1) < y(m2)) == isMax { l = m1 } else { r = m2 }
                }
                let x = (l + r) / 2, v = y(x)
                // 收紧后跑到渐近线边上（tan x）的不是极值
                guard v.isFinite, abs(v) < typical * 50 else { continue }
                out.append(.init(kind: isMax ? .maximum : .minimum, x: x, y: v))
            }
        }
        if range.contains(0), y(0).isFinite {
            out.append(.init(kind: .yIntercept, x: 0, y: y(0)))
        }
        // 同一处只留一个点：极值 > 零点 > 和 y 轴的交点（x² 在原点既是零点又是极小值）
        func rank(_ k: GraphSpecialPoint.Kind) -> Int {
            switch k {
            case .maximum, .minimum: return 0
            case .root: return 1
            case .yIntercept: return 2
            }
        }
        var unique: [GraphSpecialPoint] = []
        for p in out.sorted(by: { rank($0.kind) < rank($1.kind) })
        where !unique.contains(where: { abs($0.x - p.x) < step * 0.75 && abs($0.y - p.y) < max(typical * 1e-3, 1e-9) || ($0.kind == p.kind && abs($0.x - p.x) < step * 0.5) }) {
            unique.append(p)
        }
        return unique.sorted { $0.x < $1.x }
    }
}

/// 坐标轴刻度：1、2、5 × 10ⁿ，让相邻两条主网格线大约隔 `target` 个 point。
public enum GraphTicks {
    public static func step(unitsPerPoint: Double, target: Double = 72) -> Double {
        let raw = max(unitsPerPoint * target, 1e-12)
        let mag = Foundation.pow(10, floor(log10(raw)))
        return [1.0, 2, 5, 10].map { $0 * mag }.first { $0 >= raw * 0.999 } ?? raw
    }

    /// 次网格：1 和 5 开头的步长分 5 份，2 开头的分 4 份。
    public static func minorDivisions(of step: Double) -> Int {
        let lead = (step / Foundation.pow(10, floor(log10(step)))).rounded()
        return lead == 2 ? 4 : 5
    }

    public static func values(in range: ClosedRange<Double>, step: Double) -> [Double] {
        guard step > 0, range.upperBound - range.lowerBound < step * 400 else { return [] }
        var out: [Double] = []
        var v = (range.lowerBound / step).rounded(.up) * step
        while v <= range.upperBound {
            out.append(abs(v) < step * 1e-6 ? 0 : v)
            v += step
        }
        return out
    }

    public static func label(_ v: Double, step: Double) -> String {
        let decimals = max(0, Int(-floor(log10(step) + 1e-9)))
        if abs(v) < step * 1e-6 { return "0" }
        let s = String(format: "%.\(decimals)f", v)
        return s.replacingOccurrences(of: "-", with: "−")
    }

    /// 坐标读数：最多三位小数，去掉末尾的 0。
    public static func coordinate(_ v: Double) -> String {
        guard v.isFinite else { return "—" }
        if abs(v) >= 1e5 { return String(format: "%.2e", v) }
        var s = String(format: "%.3f", v)
        while s.contains("."), s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        if s == "-0" { s = "0" }
        return s.replacingOccurrences(of: "-", with: "−")
    }
}
