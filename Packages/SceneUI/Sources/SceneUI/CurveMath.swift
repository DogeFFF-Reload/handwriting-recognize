import Foundation

/// 两条曲线的交点、它们之间的面积（两个函数画在同一张图里时用）。
/// 只用 Foundation：取样后二分，和 GraphModel 找零点的做法一样；相切的交点用 |f − g| 的极小值补上。
public enum CurveMath {
    /// f 和 g 在 [lo, hi] 里的交点横坐标，从小到大。跨过渐近线（相邻两点差得太远）的变号不算。
    public static func intersections(_ f: (Double) -> Double, _ g: (Double) -> Double,
                                     in lo: Double, _ hi: Double, samples: Int = 1200) -> [Double] {
        guard hi > lo, lo.isFinite, hi.isFinite, samples > 2 else { return [] }
        let step = (hi - lo) / Double(samples)
        var xs: [Double] = [], ds: [Double] = []
        for i in 0...samples {
            let x = lo + Double(i) * step
            xs.append(x)
            ds.append(f(x) - g(x))
        }
        let finite = ds.filter(\.isFinite).map(abs).sorted()
        let typical = finite.isEmpty ? 1 : max(finite[finite.count / 2], 1)
        func gap(_ x: Double) -> Double { f(x) - g(x) }

        var out: [Double] = []
        for i in 1..<xs.count {
            let a = ds[i - 1], b = ds[i]
            guard a.isFinite, b.isFinite else { continue }
            if a == 0 { out.append(xs[i - 1]); continue }
            guard a * b < 0, abs(a - b) < typical * 20 else { continue }
            var l = xs[i - 1], r = xs[i]
            for _ in 0..<60 {
                let m = (l + r) / 2
                if (gap(m) < 0) == (gap(l) < 0) { l = m } else { r = m }
            }
            out.append((l + r) / 2)
        }
        if let last = ds.last, last == 0, let x = xs.last { out.append(x) }
        // 相切：f − g 不变号，但 |f − g| 在这里贴到 0
        for i in 1..<(xs.count - 1) {
            let a = ds[i - 1], b = ds[i], c = ds[i + 1]
            guard a.isFinite, b.isFinite, c.isFinite, a * c > 0, abs(b) <= abs(a), abs(b) <= abs(c) else { continue }
            var l = xs[i - 1], r = xs[i + 1]
            for _ in 0..<80 {
                let m1 = l + (r - l) / 3, m2 = r - (r - l) / 3
                if abs(gap(m1)) < abs(gap(m2)) { r = m2 } else { l = m1 }
            }
            let x = (l + r) / 2
            let scale = max(1, abs(f(x)), abs(g(x)))
            if abs(gap(x)) < 1e-7 * scale { out.append(x) }
        }
        out.sort()
        var merged: [Double] = []
        // 相切的点只能收紧到 1e-8 左右：离整数这么近就当整数
        for x in out where merged.last.map({ abs($0 - x) > step * 0.5 }) ?? true {
            merged.append(abs(x - x.rounded()) < 1e-7 ? x.rounded() : x)
        }
        return merged
    }

    /// 两曲线之间的面积 ∫_a^b |f − g| dx：按交点分段，每段用 Simpson。区间里有地方没有定义时返回 nil。
    public static func areaBetween(_ f: (Double) -> Double, _ g: (Double) -> Double,
                                   from a: Double, to b: Double, samples: Int = 400) -> Double? {
        let lo = min(a, b), hi = max(a, b)
        guard lo.isFinite, hi.isFinite else { return nil }
        guard hi > lo else { return 0 }
        let cuts = [lo] + intersections(f, g, in: lo, hi).filter { $0 > lo && $0 < hi } + [hi]
        var total = 0.0
        for k in 1..<cuts.count {
            guard let s = simpson({ f($0) - g($0) }, cuts[k - 1], cuts[k], samples) else { return nil }
            total += abs(s)
        }
        return total
    }

    static func simpson(_ h: (Double) -> Double, _ a: Double, _ b: Double, _ count: Int) -> Double? {
        let n = max(2, count + count % 2)
        let step = (b - a) / Double(n)
        var sum = h(a) + h(b)
        for i in 1..<n {
            sum += h(a + Double(i) * step) * (i % 2 == 1 ? 4 : 2)
        }
        let v = sum * step / 3
        return v.isFinite ? v : nil
    }
}
