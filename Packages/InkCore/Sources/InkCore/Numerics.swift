import Foundation

// 数值方法：极限、定积分、级数、方程的根，以及把算出来的小数认回 π/4、e − 1、√2、分数这样的封闭形式。
// 符号方法（代入、洛必达、原函数、求和公式）算不出来时用它；符号方法算出来了也用它对一遍。

public enum Numerics {
    /// 数值结果：有限值、±∞，或者没有（附原因）。
    public struct Estimate: Equatable {
        public enum Kind: Equatable { case finite, infinite, none }
        public var kind: Kind
        /// finite：值；infinite：±∞。
        public var number: Double
        /// 误差估计（finite 时）。
        public var error: Double
        /// none 时的原因；finite 时也可能附一句说明（「只在右侧有定义」）。
        public var note: String?

        public var value: Double? { kind == .none ? nil : number }

        static func finite(_ v: Double, error: Double, note: String? = nil) -> Estimate {
            Estimate(kind: .finite, number: v, error: error, note: note)
        }
        static func infinite(_ sign: Double) -> Estimate {
            Estimate(kind: .infinite, number: sign < 0 ? -.infinity : .infinity, error: 0)
        }
        static func none(_ note: String) -> Estimate {
            Estimate(kind: .none, number: .nan, error: .infinity, note: note)
        }
    }

    static let undefinedSide = "这一侧没有定义"

    // MARK: 极限

    /// x → a 时 f(x) 的极限。side：0 两侧、1 从右（a⁺）、-1 从左（a⁻）；a 可以是 ±∞。
    public static func limit(_ f: (Double) -> Double, at a: Double, side: Int = 0) -> Estimate {
        if a == .infinity { return approach { f(1 / $0) } }
        if a == -.infinity { return approach { f(-1 / $0) } }
        guard a.isFinite else { return .none("趋向的点没有定义") }
        let h0 = 0.1 * max(1, abs(a))
        let right = side >= 0 ? approach(h0: h0, distinct: { a + $0 != a }) { f(a + $0) } : nil
        let left = side <= 0 ? approach(h0: h0, distinct: { a - $0 != a }) { f(a - $0) } : nil
        switch (left, right) {
        case (nil, let r?): return r
        case (let l?, nil): return l
        case (let l?, let r?): return combine(left: l, right: r)
        default: return .none("极限不存在")
        }
    }

    static func combine(left l: Estimate, right r: Estimate) -> Estimate {
        switch (l.kind, r.kind) {
        case (.finite, .finite):
            let scale = max(1, abs(l.number), abs(r.number))
            if abs(l.number - r.number) <= 1e-6 * scale + 10 * (l.error + r.error) {
                return l.error <= r.error ? l : r
            }
            return .none("左极限 \(plain(l.number))，右极限 \(plain(r.number))，不相等，极限不存在")
        case (.infinite, .infinite):
            if l.number == r.number { return l }
            return .none("左极限 \(plain(l.number))，右极限 \(plain(r.number))，极限不存在")
        case (.none, .finite), (.none, .infinite):
            if l.note == undefinedSide { return Estimate(kind: r.kind, number: r.number, error: r.error, note: "只在右侧有定义") }
            return .none(l.note ?? "极限不存在")
        case (.finite, .none), (.infinite, .none):
            if r.note == undefinedSide { return Estimate(kind: l.kind, number: l.number, error: l.error, note: "只在左侧有定义") }
            return .none(r.note ?? "极限不存在")
        case (.finite, .infinite), (.infinite, .finite):
            return .none("左极限 \(plain(l.number))，右极限 \(plain(r.number))，极限不存在")
        case (.none, .none):
            if l.note == undefinedSide, r.note == undefinedSide { return .none("这一点附近函数没有定义") }
            return .none(r.note == undefinedSide ? (l.note ?? "极限不存在") : (r.note ?? "极限不存在"))
        }
    }

    /// h → 0⁺ 时 g(h) 的极限。h 从 h0 起每次减半：先在中等的 h 上做 Richardson 外推，
    /// 外推不收敛时再看是不是趋于 ±∞，最后用更小的 h 看函数值是不是稳定下来了（x^x、√ 型收敛慢的情形）。
    static func approach(h0: Double = 0.1, distinct: (Double) -> Bool = { _ in true }, _ g: (Double) -> Double) -> Estimate {
        var moderate: [Double] = []
        var h = h0
        for _ in 0..<15 {
            moderate.append(g(h))
            h /= 2
        }
        var deep: [Double] = []
        var k = 15
        while k < 46, distinct(h) {
            let v = g(h)
            guard v.isFinite else { break }
            deep.append(v)
            h /= 2
            k += 1
        }
        // e^{1/h} 这种：值直接溢出成 ∞
        let lastThree = moderate.suffix(3)
        if lastThree.allSatisfy({ $0 == .infinity }) { return .infinite(1) }
        if lastThree.allSatisfy({ $0 == -.infinity }) { return .infinite(-1) }
        let seq = Array(moderate.reversed().prefix { $0.isFinite }.reversed())
        guard seq.count >= 6 else { return .none(undefinedSide) }

        if let (value, error) = extrapolate(seq), error <= 1e-9 * max(1, abs(value)) {
            return .finite(value, error: error)
        }
        if let sign = divergence(seq) { return .infinite(sign) }
        if let settled = settle(seq + deep, reference: seq) { return settled }
        return .none("函数值不趋于一个确定的数，极限不存在")
    }

    /// Richardson 外推：v[k] 是步长 h0/2^k 时的值，误差按 h、h²、h³… 展开。返回最好的估计和它的误差。
    static func extrapolate(_ v: [Double]) -> (Double, Double)? {
        guard v.count >= 3 else { return nil }
        var best = (value: v[v.count - 1], error: Double.infinity)
        var prev = [v[0]]
        for i in 1..<v.count {
            var row = [v[i]]
            for j in 1...min(i, 8) {
                let f = Foundation.pow(2.0, Double(j))
                let t = row[j - 1] + (row[j - 1] - prev[j - 1]) / (f - 1)
                row.append(t)
                let err = max(abs(t - row[j - 1]), abs(t - prev[j - 1]))
                if err.isFinite, t.isFinite, err < best.error { best = (t, err) }
            }
            // 舍入误差开始占上风就停（Ridders 的做法）
            if i >= 4, abs(row[row.count - 1] - prev[prev.count - 1]) >= 2 * best.error { break }
            prev = row
        }
        return best.value.isFinite ? (best.value, best.error) : nil
    }

    /// 末尾几项单调、增量不变小：趋于 ±∞（1/h、ln h、部分和 ∑1/n 都是这样）。
    static func divergence(_ seq: [Double]) -> Double? {
        let s = Array(seq.suffix(6))
        guard s.count == 6 else { return nil }
        let d = zip(s.dropFirst(), s).map { $0 - $1 }
        guard d.allSatisfy({ $0 > 0 }) || d.allSatisfy({ $0 < 0 }) else { return nil }
        let ratios = zip(d.dropFirst(), d).map { abs($0) / abs($1) }
        guard ratios.allSatisfy({ $0 >= 0.97 }), abs(d[d.count - 1]) > 1e-6 * max(1, abs(s[s.count - 1])) else { return nil }
        return d[0] > 0 ? 1 : -1
    }

    /// 连着三步几乎不变：收敛到这个值（近似）。要和外推那段的走势一致，避免小 h 下相消误差把值弄成 0。
    static func settle(_ c: [Double], reference seq: [Double]) -> Estimate? {
        guard c.count >= 4, seq.count >= 5 else { return nil }
        let last = seq[seq.count - 1]
        let step = (1...4).map { abs(seq[seq.count - $0] - seq[seq.count - $0 - 1]) }.max()!
        for i in 0..<(c.count - 3) {
            let scale = max(1, abs(c[i]))
            let small = (i..<(i + 3)).allSatisfy { abs(c[$0 + 1] - c[$0]) <= 1e-7 * scale }
            guard small else { continue }
            let v = c[i + 3]
            guard abs(v - last) <= 20 * step + 1e-7 * scale else { return nil }
            return .finite(v, error: max(abs(c[i + 3] - c[i + 2]), 1e-9 * scale))
        }
        return nil
    }

    // MARK: 定积分

    /// ∫_a^b f(x) dx（a、b 可以是 ±∞）。breakpoints：区间里的间断点、尖点（拆开来积）。发散或算不准时返回 nil。
    public static func integrate(_ f: (Double) -> Double, _ a: Double, _ b: Double, breakpoints: [Double] = []) -> Double? {
        quadrature(f, a, b, breakpoints: breakpoints)?.value
    }

    public static func quadrature(_ f: (Double) -> Double, _ a: Double, _ b: Double,
                                  breakpoints: [Double] = []) -> (value: Double, error: Double)? {
        if a == b { return (0, 0) }
        if a > b { return quadrature(f, b, a, breakpoints: breakpoints).map { (-$0.value, $0.error) } }
        var cuts = [a] + breakpoints.filter { $0 > a && $0 < b && $0.isFinite }.sorted() + [b]
        if !a.isFinite, !b.isFinite, cuts.count == 2 { cuts = [a, 0, b] }
        var total = 0.0, error = 0.0
        for (lo, hi) in zip(cuts, cuts.dropFirst()) where hi > lo {
            guard let part = segment(f, lo, hi) else { return nil }
            total += part.value
            error += part.error
        }
        return total.isFinite ? (total, error) : nil
    }

    private static func segment(_ f: (Double) -> Double, _ a: Double, _ b: Double) -> (value: Double, error: Double)? {
        switch (a.isFinite, b.isFinite) {
        case (true, true):
            return tanhSinh(a, b) { x, _, _ in f(x) }
        case (true, false):
            // [a, ∞)：x = a + t/(1−t)
            return tanhSinh(0, 1) { t, _, rest in
                let fx = f(a + t / rest)
                return fx == 0 ? 0 : fx / (rest * rest)
            } ?? oscillatory({ f(a + $0) })
        case (false, true):
            return tanhSinh(0, 1) { t, _, rest in
                let fx = f(b - t / rest)
                return fx == 0 ? 0 : fx / (rest * rest)
            } ?? oscillatory({ f(b - $0) })
        case (false, false):
            guard let l = segment(f, a, 0), let r = segment(f, 0, b) else { return nil }
            return (l.value + r.value, l.error + r.error)
        }
    }

    /// 双指数（tanh-sinh）求积：端点有奇点（1/√x、ln x）也照样准。
    /// g(x, x − a, b − x)：后两个是到两端的距离，靠近端点时比 x 本身准。
    static func tanhSinh(_ a: Double, _ b: Double, _ g: (Double, Double, Double) -> Double) -> (value: Double, error: Double)? {
        let width = b - a
        let tMax = 4.0
        var failed = false
        var tail = 0.0
        func term(_ t: Double, recordTail: Bool) -> Double {
            let u = Double.pi / 2 * sinh(t)
            let q = exp(-2 * abs(u))
            let near = width * q / (1 + q), far = width / (1 + q)
            let (x, dLo, dHi) = t >= 0 ? (b - near, far, near) : (a + near, near, far)
            guard dLo > 0, dHi > 0 else { return 0 }
            let w = width / 2 * Double.pi / 2 * cosh(t) * 4 * q / ((1 + q) * (1 + q))
            let fx = g(x, dLo, dHi)
            guard fx.isFinite else {
                if min(dLo, dHi) > 1e-10 * width { failed = true }
                return 0
            }
            let c = w * fx
            if recordTail, abs(t) >= tMax - 0.25 { tail = max(tail, abs(c)) }
            return c
        }
        var h = 0.5
        var sum = term(0, recordTail: false)
        var k = 1
        while Double(k) * h <= tMax {
            sum += term(Double(k) * h, recordTail: false) + term(-Double(k) * h, recordTail: false)
            k += 1
        }
        var estimate = h * sum
        var diff = Double.infinity
        for level in 1...7 {
            h /= 2
            tail = 0
            var j = 1
            while Double(j) * h <= tMax {
                sum += term(Double(j) * h, recordTail: true) + term(-Double(j) * h, recordTail: true)
                j += 2
            }
            let next = h * sum
            diff = abs(next - estimate)
            estimate = next
            if failed { return nil }
            if level >= 3, diff <= 1e-12 * max(1, abs(next)) { break }
        }
        guard !failed, estimate.isFinite else { return nil }
        // 两端的贡献降不下来：积分发散（1/x 在 0 附近）
        guard tail <= 1e-6 * max(1, abs(estimate)) else { return nil }
        guard diff <= 1e-7 * max(1, abs(estimate)) else { return nil }
        return (estimate, diff)
    }

    /// ∫_0^∞ g(t) dt，g 来回变号、振幅慢慢变小（sin x / x）：在相邻零点之间分段积分，
    /// 得到一个交错级数，再用反复取平均（Euler 变换）加速。振幅不变小（sin x）时返回 nil：发散。
    static func oscillatory(_ g: (Double) -> Double) -> (value: Double, error: Double)? {
        let zeros = roots(g, in: 0, 400, samples: 80000).filter { $0 > 1e-9 }
        guard zeros.count >= 30 else { return nil }
        var partials: [Double] = [], parts: [Double] = []
        var acc = 0.0, lo = 0.0
        for z in zeros.prefix(48) {
            guard let part = tanhSinh(lo, z, { x, _, _ in g(x) }) else { return nil }
            acc += part.value
            parts.append(part.value)
            partials.append(acc)
            lo = z
        }
        // 要是交错、振幅越来越小
        let tail = Array(parts.suffix(16))
        guard zip(tail, tail.dropFirst()).allSatisfy({ ($0 < 0) != ($1 < 0) && abs($1) < abs($0) }) else { return nil }
        func euler(_ s: [Double]) -> Double {
            var row = s
            while row.count > 1 { row = zip(row, row.dropFirst()).map { ($0 + $1) / 2 } }
            return row[0]
        }
        let a = euler(Array(partials.suffix(16))), b = euler(Array(partials.dropLast(2).suffix(16)))
        let err = abs(a - b)
        guard err <= 1e-8 * max(1, abs(a)) else { return nil }
        return (a, err)
    }

    // MARK: 级数

    /// ∑_{k=lower}^{upper} term(k)（upper 可以是 +∞）；product 为 true 时是连乘 ∏。
    public static func series(_ term: (Double) -> Double, from lower: Double, to upper: Double, product: Bool = false) -> Estimate {
        guard lower.isFinite, abs(lower - lower.rounded()) < 1e-9 else { return .none("下界要是整数") }
        let start = lower.rounded()
        if upper.isFinite {
            guard abs(upper - upper.rounded()) < 1e-9 else { return .none("上界要是整数") }
            let end = upper.rounded()
            if end < start { return .finite(product ? 1 : 0, error: 0) }
            guard end - start <= 5_000_000 else { return .none("项数太多了") }
            var acc = product ? 1.0 : 0.0, comp = 0.0
            var k = start
            while k <= end {
                let t = term(k)
                guard t.isFinite else { return .none("第 \(Int(k)) 项没有定义") }
                if product { acc *= t } else { kahan(&acc, &comp, t) }
                k += 1
            }
            return .finite(acc, error: abs(acc) * 1e-15)
        }
        guard upper == .infinity else { return .none("上界不能是 −∞") }
        // 无穷级数：每 8·2^j 项记一次部分和（项数都是偶数，交错级数也能外推）
        var partials: [Double] = [], lastTerms: [Double] = []
        var acc = product ? 1.0 : 0.0, comp = 0.0
        var k = start, count = 0, next = 8
        while partials.count < 15 {
            let t = term(k)
            guard t.isFinite else { return .none("第 \(Int(k)) 项没有定义") }
            if product { acc *= t } else { kahan(&acc, &comp, t) }
            count += 1
            k += 1
            if count == next {
                partials.append(acc)
                lastTerms.append(t)
                next *= 2
            }
        }
        if !product {
            // 通项不趋于 0：发散
            let tail = lastTerms.suffix(4).map(abs)
            let scale = max(1, partials.map(abs).max() ?? 1)
            if tail[tail.count - 1] > 1e-9 * scale, zip(tail.dropFirst(), tail).allSatisfy({ $0 >= 0.9 * $1 }) {
                if let sign = divergence(partials) { return .infinite(sign) }
                return .none("通项不趋于 0，级数发散")
            }
        }
        if let (value, error) = extrapolate(partials), error <= 1e-10 * max(1, abs(value)) {
            return .finite(value, error: error)
        }
        if let sign = divergence(partials) { return .infinite(sign) }
        if let (value, error) = extrapolate(partials), error <= 1e-6 * max(1, abs(value)) {
            return .finite(value, error: error)
        }
        return .none("部分和收敛得太慢，算不准")
    }

    private static func kahan(_ sum: inout Double, _ comp: inout Double, _ x: Double) {
        let y = x - comp
        let t = sum + y
        comp = (t - sum) - y
        sum = t
    }

    // MARK: 方程的根

    /// [lo, hi] 里 f 的实根：扫描找变号再二分；不变号的重根（(x−1)²、sin x + 1）用 |f| 的极小值找。
    public static func roots(_ f: (Double) -> Double, in lo: Double, _ hi: Double, samples: Int = 4000) -> [Double] {
        guard hi > lo, samples > 2 else { return [] }
        let step = (hi - lo) / Double(samples)
        var xs: [Double] = [], vs: [Double] = []
        for i in 0...samples {
            let x = lo + Double(i) * step
            xs.append(x)
            vs.append(f(x))
        }
        var found: [Double] = []
        for i in 0...samples {
            let v = vs[i]
            if v == 0 { found.append(xs[i]); continue }
            if i > 0, vs[i - 1].isFinite, v.isFinite, vs[i - 1] != 0, (vs[i - 1] < 0) != (v < 0) {
                let r = bisect(f, xs[i - 1], xs[i])
                // 极点两边也变号：根处的函数值应该很小
                if abs(f(r)) <= 1e-8 * max(1, abs(vs[i - 1]), abs(v)) { found.append(r) }
            }
            if i > 0, i < samples, v.isFinite, vs[i - 1].isFinite, vs[i + 1].isFinite,
               abs(v) < abs(vs[i - 1]), abs(v) <= abs(vs[i + 1]), (vs[i - 1] < 0) == (v < 0), (vs[i + 1] < 0) == (v < 0) {
                let m = minimizeAbs(f, xs[i - 1], xs[i + 1])
                if abs(f(m)) <= 1e-12 * max(1, abs(vs[i - 1])) { found.append(m) }
            }
        }
        found.sort()
        var out: [Double] = []
        for r in found where out.last.map({ abs($0 - r) > 1e-6 * max(1, abs(r)) }) ?? true { out.append(r) }
        return out
    }

    static func bisect(_ f: (Double) -> Double, _ a0: Double, _ b0: Double) -> Double {
        var a = a0, b = b0
        var fa = f(a)
        for _ in 0..<200 {
            let m = (a + b) / 2
            guard m != a, m != b else { break }
            let fm = f(m)
            if fm == 0 { return m }
            if (fm < 0) == (fa < 0) { a = m; fa = fm } else { b = m }
        }
        return (a + b) / 2
    }

    static func minimizeAbs(_ f: (Double) -> Double, _ a0: Double, _ b0: Double) -> Double {
        let phi = (5.0.squareRoot() - 1) / 2
        var a = a0, b = b0
        var c = b - phi * (b - a), d = a + phi * (b - a)
        for _ in 0..<200 {
            if abs(f(c)) < abs(f(d)) { b = d } else { a = c }
            c = b - phi * (b - a)
            d = a + phi * (b - a)
            if b - a < 1e-15 * max(1, abs(a)) { break }
        }
        return (a + b) / 2
    }

    // MARK: 认回封闭形式

    /// 小数 → 准确的式子：整数、分数、π 的倍数、π²、√π、e 的幂、根式、ln、以及 e − 1、π/2 − 1 这样的组合。认不出返回 nil。
    /// tolerance 是相对误差：结果算得越准，允许的分母越大。
    public static func closedForm(_ v: Double, tolerance: Double = 1e-10) -> MathExpr? {
        guard v.isFinite else { return nil }
        let tol = tolerance * max(1, abs(v))
        if abs(v - v.rounded()) <= tol { return .number(v.rounded() == 0 ? 0 : v.rounded()) }
        let maxQ = max(12, min(10000, Int((1e-3 / tolerance).squareRoot())))
        if let (p, q) = rational(v, maxDenominator: maxQ, tolerance: tol) { return fraction(p, q) }

        let e = MathExpr.euler, pi = Double.pi
        let multiples: [(Double, MathExpr, Int)] = [
            (pi, MathExpr.pi, 12), (pi * pi, .power(MathExpr.pi, .number(2)), 36), (pi.squareRoot(), .call("sqrt", [MathExpr.pi]), 12),
            (pi * pi * pi * pi, .power(MathExpr.pi, .number(4)), 90),
            (e, MathExpr.e, 12), (e * e, .power(MathExpr.e, .number(2)), 12), (1 / e, .power(MathExpr.e, .number(-1)), 12),
            (1 / (e * e), .power(MathExpr.e, .number(-2)), 12), (e.squareRoot(), .call("sqrt", [MathExpr.e]), 12),
            (log(2), .call("ln", [.number(2)]), 6), (log(3), .call("ln", [.number(3)]), 6),
            (log(5), .call("ln", [.number(5)]), 4), (log(10), .call("ln", [.number(10)]), 4),
        ]
        for (c, expr, q) in multiples {
            if let (a, b) = rational(v / c, maxDenominator: q, tolerance: tol / c), abs(a) <= 100 { return scaled(a, b, expr) }
        }
        // 根式：v² 是分数
        if let (p, q) = rational(v * v, maxDenominator: 100, tolerance: 2 * abs(v) * tol), p > 0, p <= 100_000 {
            let r = surd(p * q)   // √(p/q) = √(pq)/q
            let g = gcd(r.outside, q)
            let root: MathExpr = .call("sqrt", [.number(Double(r.inside))])
            let e = scaled(r.outside / g, q / g, root)
            return v < 0 ? .negate(e) : e
        }
        // ln(p/q)
        let ev = exp(v)
        if v.magnitude < 12, let (p, q) = rational(ev, maxDenominator: 12, tolerance: ev * tol), p > 0, p <= 1000, p != q {
            if q == 1 { return .call("ln", [.number(Double(p))]) }
            if p == 1 { return .negate(.call("ln", [.number(Double(q))])) }
            return .call("ln", [fraction(p, q)])
        }
        // s·c + 分数：e − 1、π/2 − 1、1 − 2/e
        let symbols: [(Double, MathExpr)] = [(pi, MathExpr.pi), (e, MathExpr.e), (1 / e, .power(MathExpr.e, .number(-1))),
                                             (log(2), .call("ln", [.number(2)]))]
        for (c, expr) in symbols {
            for b in [1, 2, 3, 4, 6] {
                for a in -6...6 where a != 0 && gcd(abs(a), b) == 1 {
                    let rest = v - Double(a) / Double(b) * c
                    guard let (p, q) = rational(rest, maxDenominator: 12, tolerance: tol), p != 0, abs(p) <= 50 else { continue }
                    let s = scaled(abs(a), b, expr), r = fraction(abs(p), q)
                    switch (a > 0, p > 0) {
                    case (true, true): return .add(s, r)
                    case (true, false): return .subtract(s, r)
                    case (false, true): return .subtract(r, s)
                    case (false, false): return .negate(.add(s, r))
                    }
                }
            }
        }
        // (m ± √n)/d：黄金比例、二次方程的根
        for d in 1...4 {
            for m in -12...12 {
                let w = Double(d) * v - Double(m)
                let n = (w * w).rounded()
                guard n >= 2, n <= 1000, abs(w * w - n) <= 2 * abs(w) * Double(d) * tol else { continue }
                let r = surd(Int(n))
                guard r.inside > 1 else { continue }
                let root: MathExpr = r.outside == 1 ? .call("sqrt", [.number(Double(r.inside))])
                    : .multiply(.number(Double(r.outside)), .call("sqrt", [.number(Double(r.inside))]))
                let top: MathExpr = m == 0 ? (w < 0 ? .negate(root) : root)
                    : w < 0 ? .subtract(.number(Double(m)), root) : .add(.number(Double(m)), root)
                return d == 1 ? top : .divide(top, .number(Double(d)))
            }
        }
        return nil
    }

    /// 连分数找最简分数 p/q（q ≤ maxDenominator，|v − p/q| ≤ tolerance）。
    static func rational(_ v: Double, maxDenominator: Int, tolerance: Double) -> (Int, Int)? {
        guard v.isFinite, abs(v) < 1e12 else { return nil }
        var x = v
        var h0 = 0.0, h1 = 1.0, k0 = 1.0, k1 = 0.0
        for _ in 0..<40 {
            let a = x.rounded(.down)
            (h0, h1) = (h1, a * h1 + h0)
            (k0, k1) = (k1, a * k1 + k0)
            if k1 > Double(maxDenominator) { return nil }
            if abs(v - h1 / k1) <= tolerance { return (Int(h1), Int(k1)) }
            let frac = x - a
            guard frac > 1e-15 else { return nil }
            x = 1 / frac
        }
        return nil
    }

    static func fraction(_ p: Int, _ q: Int) -> MathExpr {
        let e: MathExpr = q == 1 ? .number(Double(abs(p))) : .divide(.number(Double(abs(p))), .number(Double(q)))
        return p < 0 ? .negate(e) : e
    }

    /// (p/q)·expr，写成 \frac{p\pi}{q} 的样子。
    static func scaled(_ p: Int, _ q: Int, _ expr: MathExpr) -> MathExpr {
        let top: MathExpr = abs(p) == 1 ? expr : .multiply(.number(Double(abs(p))), expr)
        let e: MathExpr = q == 1 ? top : .divide(top, .number(Double(q)))
        return p < 0 ? .negate(e) : e
    }

    /// √n = outside·√inside（inside 不含平方因子）。
    static func surd(_ n: Int) -> (outside: Int, inside: Int) {
        var outside = 1, inside = n, f = 2
        while f * f <= inside {
            while inside % (f * f) == 0 {
                inside /= f * f
                outside *= f
            }
            f += 1
        }
        return (outside, inside)
    }

    static func gcd(_ a: Int, _ b: Int) -> Int {
        var (x, y) = (abs(a), abs(b))
        while y != 0 { (x, y) = (y, x % y) }
        return max(x, 1)
    }

    /// 写在提示里的数（不是 LaTeX）：整数照写，其余 4 位有效数字。
    static func plain(_ v: Double) -> String {
        if v == .infinity { return "+∞" }
        if v == -.infinity { return "−∞" }
        if abs(v - v.rounded()) < 1e-9 { return String(Int(v.rounded())) }
        return String(format: "%.4g", v)
    }
}
