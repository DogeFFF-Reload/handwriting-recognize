import Foundation

// 不定积分：高中到大一常见的几类——多项式、有理函数、一次式代换、凑微分、分部积分。
// 算出原函数后求导再对一遍，对不上就当算不出来（宁可不给，也不给错的）。

public enum Integrator {
    /// ∫ f dv（不含 + C）；没找到初等的原函数时返回 nil。
    public static func antiderivative(_ f: MathExpr, _ v: String) -> MathExpr? {
        // (2x+1)^5 不展开：直接 \frac{(2x + 1)^{6}}{12}
        if let F = linearPower(f, v), verify(F, f, v) { return F }
        let g = f.simplified(v)
        guard let F = integrate(g, v, depth: 0)?.simplified(v), verify(F, g, v) else { return nil }
        return F
    }

    // MARK: 规则

    static func integrate(_ f: MathExpr, _ v: String, depth: Int) -> MathExpr? {
        guard depth < 8 else { return nil }
        let x = MathExpr.symbol(v)
        if !f.depends(on: v) { return .multiply(f, x) }
        if let p = f.polynomial(in: v) { return MathExpr.fromPolynomial(polyIntegral(p), v) }
        if let (n, d) = asRational(f, v), degree(d) >= 1, let r = rationalIntegral(n, d, v) { return r }
        switch f {
        case .negate(let a):
            return integrate(a, v, depth: depth + 1).map { .negate($0) }
        case .add(let a, let b):
            guard let A = integrate(a, v, depth: depth + 1), let B = integrate(b, v, depth: depth + 1) else { return nil }
            return .add(A, B)
        case .subtract(let a, let b):
            guard let A = integrate(a, v, depth: depth + 1), let B = integrate(b, v, depth: depth + 1) else { return nil }
            return .subtract(A, B)
        case .multiply(let a, let b):
            if !a.depends(on: v) { return integrate(b, v, depth: depth + 1).map { .multiply(a, $0) } }
            if !b.depends(on: v) { return integrate(a, v, depth: depth + 1).map { .multiply(b, $0) } }
            return product(f, v, depth: depth)
        case .divide(let a, let b):
            if !b.depends(on: v) { return integrate(a, v, depth: depth + 1).map { .divide($0, b) } }
            if !a.depends(on: v), let r = reciprocal(b, v) { return .multiply(a, r) }
            if let c = constantRatio(a, b.derivative(v), v) { return .multiply(c, log(of: b, v)) }   // u'/u
            return product(.multiply(a, .power(b, .number(-1))), v, depth: depth)
        case .power(let base, let e):
            return power(base, e, v, depth: depth)
        case .call("log", let args) where args.count == 2:
            return integrate(.divide(.call("ln", [args[1]]), .call("ln", [args[0]])), v, depth: depth + 1)
        case .call(let name, let args) where args.count == 1:
            if let k = slope(args[0], v), let F = base(name, args[0]) { return .divide(F, k) }
            // ln(x² + 1)、arctan(2x²)：当成 1·g(x) 分部积分
            return logParts([0: 1], f, v, depth: depth)
        default:
            return nil
        }
    }

    /// c·(ax + b)^n（n ≥ 2 的整数）：c·(ax + b)^{n+1} / ((n+1)a)。
    static func linearPower(_ f: MathExpr, _ v: String) -> MathExpr? {
        var c = 1.0, g = f
        if case .negate(let a) = g { c = -1; g = a }
        if case .multiply(let a, let b) = g, let k = a.constantValue { c *= k; g = b }
        guard case .power(let b, let e) = g, let n = e.constantValue, n >= 2, n <= 20, n == n.rounded(),
              let p = b.polynomial(in: v), degree(p) == 1, p.count == 2, let a = p[1] else { return nil }
        let coef = c / ((n + 1) * a)
        let pw = MathExpr.power(MathExpr.fromPolynomial(p, v), .number(n + 1))
        if let (num, den) = Numerics.rational(coef, maxDenominator: 1000, tolerance: 1e-12 * max(1, abs(coef))), abs(num) == 1 {
            let e: MathExpr = den == 1 ? pw : .divide(pw, .number(Double(den)))
            return num < 0 ? .negate(e) : e
        }
        return .multiply(number(coef), pw)
    }

    /// u 是一次式时返回 u'（可以带参数：sin(ax)）。
    static func slope(_ u: MathExpr, _ v: String) -> MathExpr? {
        let du = u.derivative(v)
        guard !du.depends(on: v), du.constantValue != 0, du.constantValue?.isFinite ?? true else { return nil }
        return du
    }

    /// ∫ name(u) du。
    static func base(_ name: String, _ u: MathExpr) -> MathExpr? {
        func c(_ n: String, _ a: MathExpr = u) -> MathExpr { .call(n, [a]) }
        switch name {
        case "sin": return .negate(c("cos"))
        case "cos": return c("sin")
        case "tan": return .negate(c("ln", c("abs", c("cos"))))
        case "cot": return c("ln", c("abs", c("sin")))
        case "sec": return c("ln", c("abs", .add(c("sec"), c("tan"))))
        case "csc": return .negate(c("ln", c("abs", .add(c("csc"), c("cot")))))
        case "sinh": return c("cosh")
        case "cosh": return c("sinh")
        case "tanh": return c("ln", c("cosh"))
        case "exp": return .power(MathExpr.e, u)
        case "ln": return .subtract(.multiply(u, c("ln")), u)
        case "lg": return .divide(.subtract(.multiply(u, c("ln")), u), c("ln", .number(10)))
        case "arctan": return .subtract(.multiply(u, c("arctan")),
                                        .multiply(.number(0.5), c("ln", .add(.number(1), .power(u, .number(2))))))
        case "arcsin": return .add(.multiply(u, c("arcsin")), c("sqrt", .subtract(.number(1), .power(u, .number(2)))))
        case "arccos": return .subtract(.multiply(u, c("arccos")), c("sqrt", .subtract(.number(1), .power(u, .number(2)))))
        case "sqrt": return .multiply(.divide(.number(2), .number(3)), .power(u, .number(1.5)))
        case "abs": return .divide(.multiply(u, c("abs")), .number(2))
        default: return nil
        }
    }

    /// ∫ base^e。
    static func power(_ b: MathExpr, _ e: MathExpr, _ v: String, depth: Int) -> MathExpr? {
        if !e.depends(on: v) {
            if let k = slope(b, v) {
                if e.constantValue == -1 { return .divide(log(of: b, v), k) }
                let n1: MathExpr = .add(e, .number(1))
                return .divide(.power(b, n1), .multiply(n1, k))
            }
            if case .call(let name, let args) = b, args.count == 1, let k = slope(args[0], v), let n = e.constantValue {
                let u = args[0]
                let twice: MathExpr = .call("sin", [.multiply(.number(2), u)])
                switch (name, n) {
                case ("sin", 2): return .divide(.subtract(.divide(u, .number(2)), .divide(twice, .number(4))), k)
                case ("cos", 2): return .divide(.add(.divide(u, .number(2)), .divide(twice, .number(4))), k)
                case ("tan", 2): return .divide(.subtract(.call("tan", [u]), u), k)
                case ("cos", -2), ("sec", 2): return .divide(.call("tan", [u]), k)
                case ("sin", -2), ("csc", 2): return .divide(.negate(.call("cot", [u])), k)
                default: break
                }
            }
            if e.constantValue == -1 { return reciprocal(b, v) }
            return product(.power(b, e), v, depth: depth)
        }
        if !b.depends(on: v), let k = slope(e, v) {
            // a^u = a^u / ln a；e^u = e^u
            if b == MathExpr.e { return .divide(.power(b, e), k) }
            return .divide(.power(b, e), .multiply(.call("ln", [b]), k))
        }
        return product(.power(b, e), v, depth: depth)
    }

    /// ∫ 1/b。
    static func reciprocal(_ b: MathExpr, _ v: String) -> MathExpr? {
        if let k = slope(b, v) { return .divide(log(of: b, v), k) }
        switch b {
        case .power(let u, let n) where !n.depends(on: v):
            guard let k = slope(u, v) else { break }
            if n.constantValue == 1 { return .divide(log(of: u, v), k) }
            let m: MathExpr = .subtract(.number(1), n)
            return .divide(.power(u, m), .multiply(m, k))
        case .power(let a, let u) where !a.depends(on: v):
            guard let k = slope(u, v) else { break }
            let inv: MathExpr = .power(a, .negate(u))
            return .negate(.divide(inv, a == MathExpr.e ? k : .multiply(.call("ln", [a]), k)))
        case .call("sqrt", let args) where args.count == 1:
            let w = args[0]
            if let k = slope(w, v) { return .divide(.multiply(.number(2), b), k) }
            // 1/√(Ax² + Bx + C)：A < 0 是 arcsin，A > 0 是 ln
            guard let p = w.polynomial(in: v), degree(p) == 2 else { break }
            let A = p[2] ?? 0, B = p[1] ?? 0, C = p[0] ?? 0
            let x = MathExpr.symbol(v)
            let shifted: MathExpr = .add(x, .number(B / (2 * A)))
            if A < 0 {
                let R2 = (B * B - 4 * A * C) / (4 * A * A)
                guard R2 > 0 else { break }
                return .divide(.call("arcsin", [.divide(shifted, number(R2.squareRoot()))]), number((-A).squareRoot()))
            }
            let inner: MathExpr = .add(.add(.multiply(.number(2 * A), x), .number(B)), .multiply(number(2 * A.squareRoot()), b))
            return .divide(.call("ln", [.call("abs", [inner])]), number(A.squareRoot()))
        case .call("cos", let args) where args.count == 1:
            return slope(args[0], v).map { .divide(base("sec", args[0])!, $0) }
        case .call("sin", let args) where args.count == 1:
            return slope(args[0], v).map { .divide(base("csc", args[0])!, $0) }
        default: break
        }
        return nil
    }

    /// 能认回根式、π 的数就写成式子（\sqrt{2}），否则就是小数。
    static func number(_ x: Double) -> MathExpr { Numerics.closedForm(x, tolerance: 1e-12) ?? .number(x) }

    /// ln|u|；u 在取样点上都是正的（x² + 1、e^x + 1）时不加绝对值。
    static func log(of u: MathExpr, _ v: String) -> MathExpr {
        let values = samplePoints.map { u.evaluate(sampleEnv(v, $0)) }.filter(\.isFinite)
        if values.count >= 3, values.allSatisfy({ $0 > 0 }) { return .call("ln", [u]) }
        return .call("ln", [.call("abs", [u])])
    }

    // MARK: 乘积：凑微分、分部积分

    static func product(_ f: MathExpr, _ v: String, depth: Int) -> MathExpr? {
        var constant: [MathExpr] = [], factors: [MathExpr] = []
        func split(_ e: MathExpr) {
            switch e {
            case .multiply(let a, let b): split(a); split(b)
            case .divide(let a, let b): split(a); split(.power(b, .number(-1)))
            case .negate(let a): constant.append(.number(-1)); split(a)
            default:
                if e.depends(on: v) { factors.append(e) } else { constant.append(e) }
            }
        }
        split(f)
        let c = constant.reduce(MathExpr.number(1)) { .multiply($0, $1) }
        guard !factors.isEmpty else { return .multiply(c, .symbol(v)) }
        if factors.count == 1, factors[0] != f, let F = integrate(factors[0], v, depth: depth + 1) { return .multiply(c, F) }
        // 凑微分：∫ g(u(x))·u'(x) dx = G(u)
        for (i, outer) in factors.enumerated() {
            let rest = factors.enumerated().filter { $0.offset != i }.map(\.element)
                .reduce(MathExpr.number(1)) { .multiply($0, $1) }
            for (u, G) in substitutions(outer, v) {
                if let k = constantRatio(rest, u.derivative(v), v) { return .multiply(.multiply(c, k), G) }
            }
        }
        // 分部积分
        if factors.count == 2 {
            for (P, g) in [(factors[0], factors[1]), (factors[1], factors[0])] {
                guard let p = P.polynomial(in: v), degree(p) >= 1 else { continue }
                if let r = tabular(p, g, v, depth: depth) { return .multiply(c, r) }
                if let r = logParts(p, g, v, depth: depth) { return .multiply(c, r) }
            }
            if let r = expTrig(factors[0], factors[1], v) ?? expTrig(factors[1], factors[0], v) { return .multiply(c, r) }
        }
        return nil
    }

    /// 一个因子可以看成 g(u) 的几种方式：(u, ∫g(u)du)。
    static func substitutions(_ e: MathExpr, _ v: String) -> [(MathExpr, MathExpr)] {
        var out: [(MathExpr, MathExpr)] = []
        switch e {
        case .call(let name, let args) where args.count == 1:
            let u = args[0]
            if name == "sqrt" {
                out.append((u, .multiply(.divide(.number(2), .number(3)), .power(u, .number(1.5)))))
            } else if let G = base(name, u) {
                out.append((u, G))
            }
        case .power(let u, let n) where !n.depends(on: v):
            if n.constantValue == -1 {
                out.append((u, .call("ln", [.call("abs", [u])])))
            } else {
                out.append((u, .divide(.power(u, .add(n, .number(1))), .add(n, .number(1)))))
            }
        case .power(let a, let u) where !a.depends(on: v):
            out.append((u, a == MathExpr.e ? e : .divide(e, .call("ln", [a]))))
        default:
            break
        }
        // 整个因子当 u：∫ u·u' = u²/2（sin x cos x、ln x / x）
        if case .symbol = e {} else { out.append((e, .divide(.power(e, .number(2)), .number(2)))) }
        return out
    }

    /// ∫ P(x)·g(x)，g 是 e^{ax+b}、sin、cos 这类积起来不变复杂的：表格法 P G₁ − P′ G₂ + P″ G₃ − …
    static func tabular(_ p: [Int: Double], _ g: MathExpr, _ v: String, depth: Int) -> MathExpr? {
        switch g {
        case .power(let a, let u) where !a.depends(on: v) && slope(u, v) != nil: break
        case .call(let n, let args) where ["sin", "cos", "sinh", "cosh", "exp"].contains(n) && args.count == 1 && slope(args[0], v) != nil: break
        default: return nil
        }
        var result: MathExpr = .number(0)
        var poly = p, G = g, sign = 1.0
        while !poly.isEmpty {
            guard let next = integrate(G, v, depth: depth + 1)?.simplified(v) else { return nil }
            result = .add(result, .multiply(.number(sign), .multiply(MathExpr.fromPolynomial(poly, v), next)))
            poly = polyDerivative(poly)
            G = next
            sign = -sign
        }
        return result
    }

    /// ∫ P(x)·g(x)，g 是 ln、arctan、arcsin（求导后变成有理式）：Q·g − ∫ Q·g′，Q = ∫P。
    static func logParts(_ p: [Int: Double], _ g: MathExpr, _ v: String, depth: Int) -> MathExpr? {
        guard case .call(let n, let args) = g, ["ln", "lg", "log", "arctan", "arcsin", "arccos"].contains(n), args.count >= 1 else { return nil }
        let Q = MathExpr.fromPolynomial(polyIntegral(p), v)
        let rest = MathExpr.multiply(Q, g.derivative(v)).simplified(v)
        guard let R = integrate(rest, v, depth: depth + 1) else { return nil }
        return .subtract(.multiply(Q, g), R)
    }

    /// ∫ e^{ax}·sin(bx)、e^{ax}·cos(bx)（循环的分部积分，直接用公式）。
    static func expTrig(_ ex: MathExpr, _ trig: MathExpr, _ v: String) -> MathExpr? {
        guard case .power(MathExpr.e, let w) = ex, let a = slope(w, v)?.constantValue,
              case .call(let n, let args) = trig, n == "sin" || n == "cos", args.count == 1,
              let b = slope(args[0], v)?.constantValue else { return nil }
        let u = args[0]
        let s: MathExpr = .call("sin", [u]), c: MathExpr = .call("cos", [u])
        let inner: MathExpr = n == "sin" ? .subtract(.multiply(.number(a), s), .multiply(.number(b), c))
                                         : .add(.multiply(.number(a), c), .multiply(.number(b), s))
        return .divide(.multiply(ex, inner), .number(a * a + b * b))
    }

    // MARK: 有理函数

    /// 把 f 写成 分子多项式 / 分母多项式（纯数字系数）。
    static func asRational(_ f: MathExpr, _ v: String) -> ([Int: Double], [Int: Double])? {
        if let p = f.polynomial(in: v) { return (p, [0: 1]) }
        switch f {
        case .negate(let a):
            return asRational(a, v).map { (scale($0.0, -1), $0.1) }
        case .add(let a, let b), .subtract(let a, let b):
            guard let (n1, d1) = asRational(a, v), let (n2, d2) = asRational(b, v) else { return nil }
            var right = mul(n2, d1)
            if case .subtract = f { right = scale(right, -1) }
            return reduce(add(mul(n1, d2), right), mul(d1, d2))
        case .multiply(let a, let b):
            guard let (n1, d1) = asRational(a, v), let (n2, d2) = asRational(b, v) else { return nil }
            return reduce(mul(n1, n2), mul(d1, d2))
        case .divide(let a, let b):
            guard let (n1, d1) = asRational(a, v), let (n2, d2) = asRational(b, v), !n2.isEmpty else { return nil }
            return reduce(mul(n1, d2), mul(d1, n2))
        case .power(let a, let e):
            guard let k = e.constantValue, k == k.rounded(), abs(k) <= 8, let (n, d) = asRational(a, v) else { return nil }
            var rn: [Int: Double] = [0: 1], rd: [Int: Double] = [0: 1]
            for _ in 0..<Int(abs(k)) {
                rn = mul(rn, n)
                rd = mul(rd, d)
            }
            return k >= 0 ? (rn, rd) : (rd, rn)
        default:
            return nil
        }
    }

    private static func reduce(_ n: [Int: Double], _ d: [Int: Double]) -> ([Int: Double], [Int: Double])? {
        guard degree(n) <= 16, degree(d) <= 16, !d.isEmpty else { return nil }
        // 分母只剩常数时并进分子
        if degree(d) == 0, let c = d[0] { return (scale(n, 1 / c), [0: 1]) }
        return (n, d)
    }

    static func rationalIntegral(_ num: [Int: Double], _ den: [Int: Double], _ v: String) -> MathExpr? {
        let x = MathExpr.symbol(v)
        let (q, r) = divide(num, den)
        var parts: [MathExpr] = []
        if !q.isEmpty { parts.append(MathExpr.fromPolynomial(polyIntegral(q), v)) }
        let n = degree(den)
        if !r.isEmpty {
            switch n {
            case 1:
                let a = den[1] ?? 0
                parts.append(.multiply(number((r[0] ?? 0) / a), .call("ln", [.call("abs", [MathExpr.fromPolynomial(den, v)])])))
            case 2:
                let a = den[2] ?? 0, b = den[1] ?? 0, c = den[0] ?? 0
                let p = r[1] ?? 0, s = r[0] ?? 0
                let Q = MathExpr.fromPolynomial(den, v)
                let D = b * b - 4 * a * c
                if p != 0 {
                    let logQ: MathExpr = D < 0 && a > 0 ? .call("ln", [Q]) : .call("ln", [.call("abs", [Q])])
                    parts.append(.multiply(number(p / (2 * a)), logQ))
                }
                let k = s - p * b / (2 * a)
                if abs(k) > 1e-14 {
                    if D < 0 {
                        let sq = (-D).squareRoot()
                        let arg = MathExpr.divide(.add(.multiply(.number(2 * a), x), .number(b)), number(sq))
                        parts.append(.multiply(number(2 * k / sq), .call("arctan", [arg])))
                    } else if D > 0 {
                        let sq = D.squareRoot()
                        let r1 = (-b + sq) / (2 * a), r2 = (-b - sq) / (2 * a)
                        let ratio = MathExpr.divide(.subtract(x, number(r1)), .subtract(x, number(r2)))
                        parts.append(.multiply(number(k / (a * (r1 - r2))), .call("ln", [.call("abs", [ratio])])))
                    } else {
                        let root = -b / (2 * a)
                        parts.append(.negate(.divide(number(k / a), .subtract(x, number(root)))))
                    }
                }
            default:
                // 分母能分解成互不相同的一次因式：部分分式 ∑ A_i ln|x − r_i|
                let lead = den[n] ?? 1
                let bound = 1 + (den.values.map(abs).max() ?? 1) / abs(lead)
                let rs = Numerics.roots({ evaluate(den, $0) }, in: -bound - 1, bound + 1, samples: 6000)
                guard rs.count == n else { return nil }
                let dden = polyDerivative(den)
                for ri in rs {
                    let A = evaluate(r, ri) / evaluate(dden, ri)
                    guard A.isFinite else { return nil }
                    if abs(A) < 1e-14 { continue }
                    parts.append(.multiply(number(A), .call("ln", [.call("abs", [.subtract(x, number(ri))])])))
                }
            }
        }
        guard var out = parts.first else { return .number(0) }
        for p in parts.dropFirst() { out = .add(out, p) }
        return out
    }

    // MARK: 多项式小工具（次数 → 系数）

    static func degree(_ p: [Int: Double]) -> Int { p.filter { abs($0.value) > 1e-14 }.keys.max() ?? -1 }

    static func clean(_ p: [Int: Double]) -> [Int: Double] { p.filter { abs($0.value) > 1e-14 } }

    static func scale(_ p: [Int: Double], _ c: Double) -> [Int: Double] { clean(p.mapValues { $0 * c }) }

    static func add(_ p: [Int: Double], _ q: [Int: Double]) -> [Int: Double] { clean(p.merging(q, uniquingKeysWith: +)) }

    static func mul(_ p: [Int: Double], _ q: [Int: Double]) -> [Int: Double] {
        var r: [Int: Double] = [:]
        for (i, a) in p { for (j, b) in q { r[i + j, default: 0] += a * b } }
        return clean(r)
    }

    static func divide(_ n: [Int: Double], _ d: [Int: Double]) -> (q: [Int: Double], r: [Int: Double]) {
        var r = clean(n), q: [Int: Double] = [:]
        let dn = degree(d)
        guard dn >= 0, let lead = d[dn] else { return ([:], r) }
        while degree(r) >= dn {
            let k = degree(r)
            let c = r[k]! / lead
            q[k - dn, default: 0] += c
            for (j, b) in d { r[j + k - dn, default: 0] -= c * b }
            r[k] = 0
            r = r.filter { abs($0.value) > 1e-12 * max(1, abs(c)) }
        }
        return (clean(q), r)
    }

    static func polyIntegral(_ p: [Int: Double]) -> [Int: Double] {
        clean(Dictionary(uniqueKeysWithValues: p.map { ($0.key + 1, $0.value / Double($0.key + 1)) }))
    }

    static func polyDerivative(_ p: [Int: Double]) -> [Int: Double] {
        clean(Dictionary(uniqueKeysWithValues: p.filter { $0.key > 0 }.map { ($0.key - 1, $0.value * Double($0.key)) }))
    }

    static func evaluate(_ p: [Int: Double], _ x: Double) -> Double {
        p.reduce(0) { $0 + $1.value * Foundation.pow(x, Double($1.key)) }
    }

    // MARK: 数值核对

    static let samplePoints: [Double] = [0.37, 0.71, 1.13, 1.57, 2.09, 2.71, 3.3, -0.53, -1.21, -2.47]

    /// 自变量取 x，其余参数取固定的非特殊值。
    static func sampleEnv(_ v: String, _ x: Double, params: Int = 0) -> [String: Double] {
        var env: [String: Double] = [v: x]
        for (i, s) in ["a", "b", "c", "k", "m", "n", "p", "q", "t", "u", "w"].enumerated() where s != v {
            env[s] = params == 0 ? 1.3 + 0.37 * Double(i) : 0.6 + 0.53 * Double(i)
        }
        return env
    }

    /// a / b 是不是与 v 无关的常数（带参数时换两组参数值都要成立）；是的话返回这个常数（写成式子）。
    static func constantRatio(_ a: MathExpr, _ b: MathExpr, _ v: String) -> MathExpr? {
        for params in 0..<2 {
            var ratios: [Double] = []
            for x in samplePoints {
                let env = sampleEnv(v, x, params: params)
                let p = a.evaluate(env), q = b.evaluate(env)
                guard p.isFinite, q.isFinite, abs(q) > 1e-9 else { continue }
                ratios.append(p / q)
            }
            guard ratios.count >= 4, let r0 = ratios.first, r0 != 0,
                  ratios.allSatisfy({ abs($0 - r0) <= 1e-9 * max(1, abs(r0)) }) else { return nil }
        }
        let params = a.symbols.union(b.symbols).subtracting([v])
        if params.isEmpty {
            let env = sampleEnv(v, samplePoints.first { b.evaluate(sampleEnv(v, $0)).isFinite && abs(b.evaluate(sampleEnv(v, $0))) > 1e-9 } ?? 1)
            return number(a.evaluate(env) / b.evaluate(env))
        }
        // 带参数：在一个取样点上代入 v，剩下的就是只含参数的常数
        guard let x = samplePoints.first(where: { abs(b.evaluate(sampleEnv(v, $0))) > 1e-9 }) else { return nil }
        let at = MathExpr.number(x)
        return MathExpr.divide(a.substituting(v, with: at), b.substituting(v, with: at)).simplified(params.sorted()[0])
    }

    /// F′ = f？在取样点上比一比（两边都有定义的点至少 3 个）。
    static func verify(_ F: MathExpr, _ f: MathExpr, _ v: String) -> Bool {
        let dF = F.derivative(v)
        var checked = 0
        for params in 0..<2 {
            for x in samplePoints + [4.4, 5.9, -3.6, 0.13] {
                let env = sampleEnv(v, x, params: params)
                let a = dF.evaluate(env), b = f.evaluate(env)
                guard a.isFinite, b.isFinite else { continue }
                guard abs(a - b) <= 1e-7 * max(1, abs(b)) else { return false }
                checked += 1
            }
        }
        return checked >= 3
    }
}
