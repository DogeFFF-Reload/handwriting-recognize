import Foundation

// 「求解」：学生写下一个完整的式子——极限、积分、求和 / 连乘、d/dx、对已有函数取值、四则运算、方程——
// 双击后直接算出结果。能用符号方法（代入、洛必达、原函数、求和公式）就给准确值，
// 不行再用数值方法，并尽量认回 π/4、e − 1、√2、分数这样的封闭形式；实在认不出就写 ≈ 小数。

/// 算出来的结果：左边是学生写的式子，右边是答案（App 里用绿色）。
public struct Solution: Equatable {
    public enum Operation: String, Equatable { case derivative, integral, limit, series, equation, evaluate }

    /// 在被引用的函数图像上标出来的东西。
    public enum Hint: Equatable {
        /// ∫_a^b f(x) dx：把 f 和 x 轴之间 a 到 b 这块涂出来。
        case area(function: String, from: Double, to: Double)
        /// lim_{x→a} f(x) = L：标出 (a, L)（空心点）。
        case point(function: String, x: Double, y: Double)
    }

    /// 写回 LaTeX 的左边（学生写的那部分，规范了一下写法）。
    public var input: String
    /// 答案的 LaTeX；没有答案（极限不存在、级数发散、算不出来）时为 nil，原因在 note。
    public var result: String?
    /// 连接左右的符号：=、\approx、\Rightarrow（方程）。
    public var relation: String
    public var note: String?
    /// note 本身就是结论（「极限不存在」「级数发散」「方程没有实数解」），不是「算不出来」。
    public var conclusive: Bool
    public var operation: Operation
    /// 用到了哪些已经写过的函数。
    public var references: [String]
    public var hint: Hint?
}

public enum Solver {
    enum Failure: Error {
        case conclusion(String)
        case unsupported(String)
    }

    enum Plan: Equatable {
        /// 普通函数：交给作图。
        case function
        /// 算 source 这一段；display 是显示用的左边。strong：一看就是要算的（有运算、有引用、纯算式）。
        case compute(source: String, display: String, strong: Bool)
        case equation(lhs: String, rhs: String)
    }

    /// 选了「函数」时要不要转去「求解」：有极限、积分、求和、d/dx，引用了写过的函数，是方程，或者是纯数字的算式。
    public static func looksLikeComputation(_ latex: String, functions: [String: FunctionDefinition] = [:]) -> Bool {
        switch plan(FunctionDefinition.firstLine(latex), functions: functions) {
        case .compute(_, _, let strong)?: return strong
        case .equation?: return true
        default: return false
        }
    }

    /// 求解。返回 nil：这一行其实是一条普通函数（f(x) = x² − 4），该去作图。解析不了时抛 FunctionDefinition.ParseError。
    public static func solve(_ latex: String, functions: [String: FunctionDefinition] = [:]) throws -> Solution? {
        let line = FunctionDefinition.firstLine(latex)
        guard let plan = plan(line, functions: functions) else {
            _ = try LatexExpression.parseExpression(splitEquals(line).lhs, functions: functions)
            throw FunctionDefinition.ParseError.empty
        }
        switch plan {
        case .function: return nil
        case .compute(let source, let display, _): return try compute(source, display: display, functions: functions)
        case .equation(let lhs, let rhs): return try equation(lhs, rhs, functions: functions)
        }
    }

    static func plan(_ line: String, functions: [String: FunctionDefinition]) -> Plan? {
        let (lhs, rhs) = splitEquals(line)
        guard let tokens = try? LatexExpression.tokenize(lhs), !tokens.isEmpty else { return nil }
        if let rhs, let header = LatexExpression.functionHeader(tokens) {
            // f(x) = …：右边有极限、积分、求和、d/dx 才是要算的（F(x) = ∫_0^x t dt）
            let others = functions.filter { $0.key != header.name }
            guard let p = try? LatexExpression.parseExpression(rhs, functions: others) else { return .function }
            if p.hasOperation { return .compute(source: rhs, display: lhs + "=" + rhs, strong: true) }
            // f 已经写过、右边是个数：f(x) = 0 是方程
            if functions[header.name] != nil, p.expr.symbols.isEmpty, tokens.count == 4 { return .equation(lhs: lhs, rhs: rhs) }
            return .function
        }
        guard let p = try? LatexExpression.parseExpression(lhs, functions: functions) else { return nil }
        let arithmetic = p.expr.symbols.isEmpty && tokens.count > 1
        let strong = p.hasOperation || !p.references.isEmpty || arithmetic
        if let rhs, !strong, !rhs.isEmpty, (try? LatexExpression.parseExpression(rhs, functions: functions)) != nil {
            return .equation(lhs: lhs, rhs: rhs)
        }
        if strong || p.expr.symbols.isEmpty { return .compute(source: lhs, display: lhs, strong: strong) }
        return .function
    }

    // MARK: 计算

    struct Context {
        /// 用了没认回封闭形式的数值结果：答案写 ≈。
        var approximate = false
        /// 有不定积分：答案后面加 + C。
        var constantOfIntegration = false
    }

    static func compute(_ source: String, display: String, functions: [String: FunctionDefinition]) throws -> Solution {
        let parsed = try LatexExpression.parseExpression(source, functions: functions)
        var sol = Solution(input: clean(display), result: nil, relation: "=", note: nil, conclusive: false,
                           operation: operation(parsed), references: parsed.references.sorted(), hint: nil)
        var ctx = Context()
        do {
            let reduced = try reduce(parsed.expr, &ctx)
            try present(reduced, top: parsed.expr, ctx: ctx, into: &sol)
            sol.hint = hint(parsed, reduced)
        } catch Failure.conclusion(let s) {
            sol.note = s
            sol.conclusive = true
        } catch Failure.unsupported(let s) {
            sol.note = s
        }
        return sol
    }

    static func operation(_ p: LatexExpression.Parsed) -> Solution.Operation {
        func first(_ e: MathExpr) -> Solution.Operation? {
            switch e {
            case .limit: return .limit
            case .integral: return .integral
            case .series: return .series
            case .number, .symbol: return nil
            case .negate(let a): return first(a)
            case .add(let a, let b), .subtract(let a, let b), .multiply(let a, let b), .divide(let a, let b), .power(let a, let b):
                return first(a) ?? first(b)
            case .call(_, let args): return args.lazy.compactMap(first).first
            }
        }
        if let op = first(p.expr) { return op }
        return p.usesDerivative ? .derivative : .evaluate
    }

    static func present(_ reduced: MathExpr, top: MathExpr, ctx: Context, into sol: inout Solution) throws {
        let free = reduced.symbols
        let plusC = ctx.constantOfIntegration ? " + C" : ""
        guard free.isEmpty else {
            let r = isBigOperator(top) ? reduced : reduced.simplified(mainVariable(free))
            sol.result = r.latex + plusC
            return
        }
        let v = reduced.evaluate([:])
        if v.isInfinite {
            sol.result = v > 0 ? "+\\infty" : "-\\infty"
            return
        }
        guard v.isFinite else { throw Failure.unsupported("结果没有定义") }
        if ctx.approximate {
            sol.relation = "\\approx"
            sol.result = approx(v)
        } else if let c = Numerics.closedForm(v, tolerance: 1e-10) {
            sol.result = c.latex + plusC
        } else if case .number = reduced {
            sol.relation = "\\approx"
            sol.result = approx(v)
        } else if reduced.latex.count <= 60, !reduced.latex.contains("?") {
            sol.result = reduced.latex + plusC
        } else {
            sol.relation = "\\approx"
            sol.result = approx(v)
        }
    }

    static func isBigOperator(_ e: MathExpr) -> Bool {
        switch e {
        case .limit, .integral, .series: return true
        default: return false
        }
    }

    static func mainVariable(_ s: Set<String>) -> String { s.contains("x") ? "x" : s.sorted().first ?? "x" }

    /// 从里往外把极限、积分、求和换成算出来的结果。
    static func reduce(_ e: MathExpr, _ c: inout Context) throws -> MathExpr {
        switch e {
        case .number, .symbol: return e
        case .negate(let a): return .negate(try reduce(a, &c))
        case .add(let a, let b): return .add(try reduce(a, &c), try reduce(b, &c))
        case .subtract(let a, let b): return .subtract(try reduce(a, &c), try reduce(b, &c))
        case .multiply(let a, let b): return .multiply(try reduce(a, &c), try reduce(b, &c))
        case .divide(let a, let b): return .divide(try reduce(a, &c), try reduce(b, &c))
        case .power(let a, let b): return .power(try reduce(a, &c), try reduce(b, &c))
        case .call(let name, let args):
            var out: [MathExpr] = []
            for a in args { out.append(try reduce(a, &c)) }
            return .call(name, out)
        case .limit(let v, let point, let side, let body):
            return try limit(try reduce(body, &c), v, try reduce(point, &c), side, &c)
        case .integral(let v, let lower, let upper, let body):
            let b = try reduce(body, &c)
            guard let lower, let upper else {
                guard let F = Integrator.antiderivative(b, v) else { throw Failure.unsupported("没有找到这个不定积分的初等原函数") }
                c.constantOfIntegration = true
                return F
            }
            return try definite(b, v, try reduce(lower, &c), try reduce(upper, &c), &c)
        case .series(let k, let lower, let upper, let body, let product):
            return try series(try reduce(body, &c), k, try reduce(lower, &c), try reduce(upper, &c), product, &c)
        }
    }

    /// 数值结果：能认回封闭形式就用式子，否则记下「近似」。
    static func exact(_ v: Double, error: Double, _ c: inout Context) -> MathExpr {
        let tol = min(1e-6, max(1e-11, 10 * error / max(1, abs(v))))
        if let e = Numerics.closedForm(v, tolerance: tol) { return e }
        c.approximate = true
        return .number(v)
    }

    // MARK: 极限

    static func limit(_ body: MathExpr, _ v: String, _ point: MathExpr, _ side: Int, _ c: inout Context) throws -> MathExpr {
        guard point.symbols.isEmpty else { throw Failure.unsupported("趋向的点要是一个确定的数") }
        let a = point.evaluate([:])
        let params = body.symbols.subtracting([v])
        if a.isFinite, let r = symbolicLimit(body, v, a, params: params) { return r }
        guard params.isEmpty else {
            throw Failure.unsupported("带字母 \(params.sorted().joined(separator: "、")) 的这个极限暂时算不出来")
        }
        let est = Numerics.limit({ body.evaluate([v: $0]) }, at: a, side: side)
        switch est.kind {
        case .finite: return exact(est.number, error: est.error, &c)
        case .infinite: return .number(est.number)
        case .none: throw Failure.conclusion(est.note ?? "极限不存在")
        }
    }

    /// 直接代入；0/0 型用洛必达（最多 4 次）。能带参数：lim_{h→0} (f(x+h) − f(x))/h = f′(x)。
    static func symbolicLimit(_ body: MathExpr, _ v: String, _ a: Double, params: Set<String>) -> MathExpr? {
        func values(_ e: MathExpr) -> [Double] {
            (0..<2).map { set in
                var env = Integrator.sampleEnv(v, a, params: set)
                env = env.filter { $0.key == v || params.contains($0.key) }
                return e.evaluate(env)
            }
        }
        var f = body
        for _ in 0..<5 {
            if values(f).allSatisfy(\.isFinite) {
                return f.substituting(v, with: .number(a)).simplified(mainVariable(params))
            }
            guard case .divide(let n, let d) = f,
                  values(n).allSatisfy({ abs($0) < 1e-9 }), values(d).allSatisfy({ abs($0) < 1e-9 }) else { return nil }
            f = .divide(n.derivative(v), d.derivative(v))
        }
        return nil
    }

    // MARK: 定积分

    static func definite(_ body: MathExpr, _ v: String, _ lower: MathExpr, _ upper: MathExpr, _ c: inout Context) throws -> MathExpr {
        let params = body.symbols.subtracting([v]).union(lower.symbols).union(upper.symbols)
        if !params.isEmpty {
            // 上下限或被积函数带字母：只能用原函数（∫_0^x t dt = x²/2）
            guard let F = Integrator.antiderivative(body, v) else { throw Failure.unsupported("没有找到原函数，带字母的定积分算不出来") }
            return MathExpr.subtract(F.substituting(v, with: upper), F.substituting(v, with: lower)).simplified(mainVariable(params))
        }
        let a = lower.evaluate([:]), b = upper.evaluate([:])
        guard !a.isNaN, !b.isNaN else { throw Failure.unsupported("积分上下限没有定义") }
        let f: (Double) -> Double = { body.evaluate([v: $0]) }
        let breaks = breakpoints(body, v, a, b)
        let numeric = Numerics.quadrature(f, a, b, breakpoints: breaks)
        // 原函数在 [a, b] 上连续时用牛顿—莱布尼茨公式，得到准确值（和数值结果对一下）
        if a.isFinite, b.isFinite, smooth(f, a, b, breaks), let F = Integrator.antiderivative(body, v) {
            let s = MathExpr.subtract(F.substituting(v, with: upper), F.substituting(v, with: lower)).simplified()
            let sv = s.evaluate([:])
            if sv.isFinite, numeric.map({ abs($0.value - sv) <= 1e-6 * max(1, abs(sv)) }) ?? true {
                if let cf = Numerics.closedForm(sv, tolerance: 1e-10) { return cf }
                if case .number = s { return exact(sv, error: 0, &c) }
                return s
            }
        }
        guard let numeric else {
            // 端点或区间内某点附近函数值冲向无穷：发散；附近没有定义：积不了
            var blowsUp = false, undefined = false
            for p in [a, b] + breaks where p.isFinite {
                let d = 1e-9 * max(1, abs(p))
                for x in [p - d, p + d] where x >= a && x <= b {
                    let y = f(x)
                    if y.isNaN { undefined = true } else if !y.isFinite || abs(y) > 1e7 { blowsUp = true }
                }
            }
            if blowsUp { throw Failure.conclusion("积分发散") }
            if undefined { throw Failure.unsupported("被积函数在积分区间里有些地方没有定义") }
            throw Failure.unsupported(a.isFinite && b.isFinite ? "数值积分不收敛，算不准" : "积分发散，或者收敛得太慢算不准")
        }
        return exact(numeric.value, error: numeric.error, &c)
    }

    /// 区间内部被积函数处处有定义（没有奇点）。
    static func smooth(_ f: (Double) -> Double, _ a: Double, _ b: Double, _ breaks: [Double]) -> Bool {
        let inside = breaks.filter { $0 > a && $0 < b }
        guard inside.allSatisfy({ f($0).isFinite }) else { return false }
        return (1..<64).allSatisfy { f(a + (b - a) * Double($0) / 64).isFinite }
    }

    /// 间断点、尖点：分母、绝对值、根号、对数里面为 0 的地方，tan 的极点。
    static func breakpoints(_ e: MathExpr, _ v: String, _ a: Double, _ b: Double) -> [Double] {
        var critical: [MathExpr] = []
        func walk(_ e: MathExpr) {
            switch e {
            case .divide(let p, let q):
                walk(p); walk(q)
                if q.depends(on: v) { critical.append(q) }
            case .power(let p, let q):
                walk(p); walk(q)
                if p.depends(on: v), let k = q.constantValue, k < 0 || k != k.rounded() { critical.append(p) }
            case .call(let name, let args):
                args.forEach(walk)
                guard let u = args.last, u.depends(on: v) else { break }
                switch name {
                case "abs", "sqrt", "ln", "lg", "log", "root": critical.append(u)
                case "tan", "sec": critical.append(.call("cos", [u]))
                case "cot", "csc": critical.append(.call("sin", [u]))
                default: break
                }
            case .negate(let p): walk(p)
            case .add(let p, let q), .subtract(let p, let q), .multiply(let p, let q): walk(p); walk(q)
            default: break
            }
        }
        walk(e)
        let lo = max(a, -1000), hi = min(b, 1000)
        guard hi > lo else { return [] }
        var out: [Double] = []
        for g in critical.prefix(8) {
            out += Numerics.roots({ g.evaluate([v: $0]) }, in: lo, hi, samples: 2000).filter { $0 > a && $0 < b }
        }
        out.sort()
        var merged: [Double] = []
        for x in out where merged.last.map({ abs($0 - x) > 1e-9 * max(1, abs(x)) }) ?? true { merged.append(x) }
        return Array(merged.prefix(24))
    }

    // MARK: 求和、连乘

    static func series(_ body: MathExpr, _ k: String, _ lower: MathExpr, _ upper: MathExpr, _ product: Bool,
                       _ c: inout Context) throws -> MathExpr {
        guard lower.symbols.isEmpty else { throw Failure.unsupported("下界要是一个数") }
        let L = lower.evaluate([:])
        guard L.isFinite, abs(L - L.rounded()) < 1e-9 else { throw Failure.unsupported("下界要是整数") }
        let params = body.symbols.subtracting([k])
        if !upper.symbols.isEmpty {
            guard let s = symbolicSeries(body, k, lower: Int(L.rounded()), upper: upper, product: product) else {
                throw Failure.unsupported(product ? "这个连乘没有找到封闭形式" : "这个和没有找到封闭形式")
            }
            return s
        }
        let U = upper.evaluate([:])
        if !params.isEmpty {
            guard U.isFinite, U - L <= 60 else { throw Failure.unsupported("通项带字母时只能算有限项") }
            var acc: MathExpr = .number(product ? 1 : 0)
            var i = L.rounded()
            while i <= U + 1e-9 {
                let t = body.substituting(k, with: .number(i))
                acc = product ? .multiply(acc, t) : .add(acc, t)
                i += 1
            }
            return acc.simplified(mainVariable(params))
        }
        let est = Numerics.series({ body.evaluate([k: $0]) }, from: L, to: U, product: product)
        switch est.kind {
        case .finite:
            return exact(est.number, error: U.isFinite ? 1e-13 * max(1, abs(est.number)) : est.error, &c)
        case .infinite:
            throw Failure.conclusion((product ? "连乘发散" : "级数发散") + "（部分" + (product ? "积" : "和") + "趋于 \(Numerics.plain(est.number))）")
        case .none:
            let note = est.note ?? "算不出来"
            throw note.contains("发散") ? Failure.conclusion(note) : Failure.unsupported(note)
        }
    }

    /// 上界是字母（一般是 n）：多项式通项 → 求和公式（尽量写成 n(n+1)(2n+1)/6 这样）；等比数列 → 公式；∏k → n!。
    static func symbolicSeries(_ body: MathExpr, _ k: String, lower L: Int, upper: MathExpr, product: Bool) -> MathExpr? {
        let name = mainVariable(upper.symbols)
        let count = MathExpr.add(.subtract(upper, .number(Double(L))), .number(1)).simplified(name)
        if product {
            if body == .symbol(k), L == 1 { return .call("factorial", [upper]) }
            if !body.depends(on: k) { return .power(body, count) }
            return nil
        }
        if !body.depends(on: k) { return MathExpr.multiply(body, count).simplified(name) }
        func closed(_ s: [Int: Double]) -> MathExpr {
            if case .symbol(let n) = upper { return factored(s, n) }
            return MathExpr.fromPolynomial(s, "§").substituting("§", with: upper).simplified(name)
        }
        if let p = body.polynomial(in: k), let s = polynomialSum(p, lower: L) { return closed(s) }
        // 和 k 无关的字母因子提到求和号外面：∑ k/n² = \frac{1}{n^2} ∑ k（黎曼和）
        let (outside, inside) = splitFactors(body, k)
        if let outside, let p = inside.polynomial(in: k), let s = polynomialSum(p, lower: L) {
            return .multiply(outside, closed(s))
        }
        guard body.symbols.subtracting([k]).isEmpty else { return nil }
        return geometricSum(body, k, lower: L, count: count, name: name)
    }

    /// body = outside · inside，outside 和 k 无关（没有这样的因子时 outside 为 nil）。
    static func splitFactors(_ body: MathExpr, _ k: String) -> (outside: MathExpr?, inside: MathExpr) {
        var top: [MathExpr] = [], bottom: [MathExpr] = [], outTop: [MathExpr] = [], outBottom: [MathExpr] = []
        func walk(_ e: MathExpr, _ up: Bool) {
            switch e {
            case .multiply(let a, let b): walk(a, up); walk(b, up)
            case .divide(let a, let b): walk(a, up); walk(b, !up)
            default:
                if e.depends(on: k) { up ? top.append(e) : bottom.append(e) } else { up ? outTop.append(e) : outBottom.append(e) }
            }
        }
        walk(body, true)
        func product(_ xs: [MathExpr]) -> MathExpr { xs.dropFirst().reduce(xs.first ?? .number(1)) { .multiply($0, $1) } }
        let inside = bottom.isEmpty ? product(top) : .divide(product(top), product(bottom))
        guard !outTop.isEmpty || !outBottom.isEmpty else { return (nil, body) }
        let outside = outBottom.isEmpty ? product(outTop) : .divide(product(outTop), product(outBottom))
        return (outside, inside)
    }

    /// ∑_{k=L}^{N} p(k) 作为 N 的多项式（牛顿插值，系数认回分数）。
    static func polynomialSum(_ p: [Int: Double], lower L: Int) -> [Int: Double]? {
        let d = (p.keys.max() ?? 0) + 1
        guard d <= 12 else { return nil }
        let N0 = Double(L - 1)
        var ys: [Double] = [], acc = 0.0
        for j in 0...d {
            if j > 0 { acc += Integrator.evaluate(p, N0 + Double(j)) }
            ys.append(acc)
        }
        var diffs: [Double] = [], row = ys
        for _ in 0...d {
            diffs.append(row[0])
            row = zip(row.dropFirst(), row).map { $0 - $1 }
        }
        // S(N) = ∑_j Δʲ·C(N − N0, j)
        var coeffs: [Int: Double] = [:], basis: [Int: Double] = [0: 1]
        for j in 0...d {
            if j > 0 { basis = Integrator.scale(Integrator.mul(basis, [1: 1, 0: -(N0 + Double(j - 1))]), 1 / Double(j)) }
            coeffs = Integrator.add(coeffs, Integrator.scale(basis, diffs[j]))
        }
        var out: [Int: Double] = [:]
        for (i, c) in coeffs {
            guard let (a, b) = Numerics.rational(c, maxDenominator: 10000, tolerance: 1e-9 * max(1, abs(c))) else { return nil }
            if a != 0 { out[i] = Double(a) / Double(b) }
        }
        return out
    }

    /// 多项式写成因式乘积：\frac{n(n+1)(2n+1)}{6}。分不干净的部分照原样乘在后面。
    static func factored(_ s: [Int: Double], _ n: String) -> MathExpr {
        var poly = Integrator.clean(s)
        guard Integrator.degree(poly) >= 1 else { return MathExpr.fromPolynomial(poly, n) }
        var roots: [(Int, Int)] = []   // (a, b)：因式 a·n + b
        var candidates: [(Int, Int)] = []
        for a in 1...6 { for b in -12...12 where Numerics.gcd(a, b) == 1 || b == 0 && a == 1 { candidates.append((a, b)) } }
        for (a, b) in candidates {
            let r = -Double(b) / Double(a)
            while Integrator.degree(poly) >= 1 {
                let scale = max(1, poly.values.map(abs).max() ?? 1)
                guard abs(Integrator.evaluate(poly, r)) <= 1e-9 * scale else { break }
                poly = Integrator.divide(poly, [1: 1, 0: -r]).q
                roots.append((a, b))
            }
        }
        let degree = Integrator.degree(poly)
        let lead = poly[degree] ?? 1
        var rest = Integrator.scale(poly, 1 / lead)   // 首一
        var lcd = 1
        for c in rest.values {
            if let (_, q) = Numerics.rational(c, maxDenominator: 1000, tolerance: 1e-9) { lcd = lcd / Numerics.gcd(lcd, q) * q }
        }
        rest = Integrator.scale(rest, Double(lcd))
        let K = lead / (roots.reduce(1.0) { $0 * Double($1.0) } * Double(lcd))

        var factors: [MathExpr] = []
        let grouped = Dictionary(grouping: roots, by: { "\($0.0),\($0.1)" })
        for key in grouped.keys.sorted(by: { lhs, rhs in
            let l = grouped[lhs]![0], r = grouped[rhs]![0]
            return l.0 != r.0 ? l.0 < r.0 : l.1 < r.1
        }) {
            let (a, b) = grouped[key]![0]
            let f = MathExpr.fromPolynomial([1: Double(a), 0: Double(b)], n)
            let m = grouped[key]!.count
            factors.append(m == 1 ? f : .power(f, .number(Double(m))))
        }
        if degree >= 1 { factors.append(MathExpr.fromPolynomial(rest, n)) }
        var prod = factors[0]
        for f in factors.dropFirst() { prod = .multiply(prod, f) }
        guard let (p, q) = Numerics.rational(K, maxDenominator: 100_000, tolerance: 1e-9 * max(1, abs(K))) else {
            return .multiply(.number(K), prod)
        }
        let top: MathExpr = abs(p) == 1 ? prod : .multiply(.number(Double(abs(p))), prod)
        let e: MathExpr = q == 1 ? top : .divide(top, .number(Double(q)))
        return p < 0 ? .negate(e) : e
    }

    /// 等比数列求和：t₀·(r^{项数} − 1)/(r − 1)，写成 2^{n+1} − 2、1 − (\frac{1}{2})^{n}、\frac{3^{n+1} − 1}{2}。
    static func geometricSum(_ body: MathExpr, _ k: String, lower L: Int, count: MathExpr, name: String) -> MathExpr? {
        func t(_ i: Int) -> Double { body.evaluate([k: Double(L + i)]) }
        let t0 = t(0)
        guard t0.isFinite, t0 != 0 else { return nil }
        let r = t(1) / t0
        guard r.isFinite, abs(r - 1) > 1e-12, r != 0,
              (2...5).allSatisfy({ abs(t($0) / t($0 - 1) - r) <= 1e-12 * max(1, abs(r)) }),
              let rE = Numerics.closedForm(r, tolerance: 1e-12) else { return nil }
        let coef = t0 / (r - 1)
        for j in 1...4 where abs(coef - Foundation.pow(r, Double(j))) <= 1e-12 * max(1, abs(coef)) {
            guard let cE = Numerics.closedForm(coef, tolerance: 1e-12) else { break }
            return .subtract(.power(rE, MathExpr.add(count, .number(Double(j))).simplified(name)), cE)
        }
        let pw = MathExpr.power(rE, count)
        if let (p, q) = Numerics.rational(coef, maxDenominator: 1000, tolerance: 1e-12 * max(1, abs(coef))), abs(p) == 1 {
            let top: MathExpr = p > 0 ? .subtract(pw, .number(1)) : .subtract(.number(1), pw)
            return q == 1 ? top : .divide(top, .number(Double(q)))
        }
        guard let cE = Numerics.closedForm(coef, tolerance: 1e-12) else { return nil }
        return .subtract(.multiply(cE, pw), cE)
    }

    // MARK: 方程

    static func equation(_ lhs: String, _ rhs: String, functions: [String: FunctionDefinition]) throws -> Solution {
        let l = try LatexExpression.parseExpression(lhs, functions: functions)
        let r = try LatexExpression.parseExpression(rhs, functions: functions)
        var sol = Solution(input: clean(lhs + "=" + rhs), result: nil, relation: "\\Rightarrow", note: nil, conclusive: false,
                           operation: .equation, references: l.references.union(r.references).sorted(), hint: nil)
        var ctx = Context()
        do {
            let e = MathExpr.subtract(try reduce(l.expr, &ctx), try reduce(r.expr, &ctx))
            let (result, note) = try solveEquation(e)
            sol.result = result
            sol.note = note
        } catch Failure.conclusion(let s) {
            sol.note = s
            sol.conclusive = true
        } catch Failure.unsupported(let s) {
            sol.note = s
        }
        return sol
    }

    static func solveEquation(_ e: MathExpr) throws -> (String, String?) {
        let free = e.symbols
        guard !free.isEmpty else {
            throw Failure.conclusion(abs(e.evaluate([:])) < 1e-9 ? "等式成立" : "等式不成立")
        }
        guard free.count == 1, let x = free.first else {
            throw Failure.unsupported("方程里有好几个未知数（\(free.sorted().joined(separator: "、"))），解不了")
        }
        let f: (Double) -> Double = { e.evaluate([x: $0]) }
        if let p = e.polynomial(in: x) {
            let n = Integrator.degree(p)
            switch n {
            case -1: throw Failure.conclusion("恒等式：\(x) 取任何值都成立")
            case 0: throw Failure.conclusion("方程无解")
            case 1: return (try rootsLatex(x, [-(p[0] ?? 0) / p[1]!]), nil)
            case 2:
                let a = p[2]!, b = p[1] ?? 0, c = p[0] ?? 0
                let D = b * b - 4 * a * c
                let scale = max(b * b, abs(4 * a * c), 1e-300)
                if D < -1e-12 * scale { throw Failure.conclusion("方程没有实数解（Δ < 0）") }
                if abs(D) <= 1e-12 * scale { return (try rootsLatex(x, [-b / (2 * a)]), nil) }
                let m = -b / (2 * a), s = D.squareRoot() / (2 * abs(a))
                let r1 = m - s, r2 = m + s
                let rational = [r1, r2].allSatisfy { Numerics.rational($0, maxDenominator: 1000, tolerance: 1e-9 * max(1, abs($0))) != nil }
                if !rational, let sE = Numerics.closedForm(s, tolerance: 1e-10), let mE = Numerics.closedForm(m, tolerance: 1e-10) {
                    return ("\(x) = " + (m == 0 ? "" : mE.latex + " ") + "\\pm " + sE.latex, nil)
                }
                return (try rootsLatex(x, [r1, r2]), nil)
            default:
                let lead = abs(p[n]!)
                let bound = 1 + (p.filter { $0.key != n }.values.map { abs($0) / lead }.max() ?? 0)
                return (try rootsLatex(x, Numerics.roots(f, in: -bound - 0.5, bound + 0.5, samples: 20000)), nil)
            }
        }
        let periodic = ["sin", "cos", "tan", "cot", "sec", "csc"].contains { callNames(e).contains($0) }
        if periodic {
            let rs = Numerics.roots(f, in: 0, 2 * Double.pi, samples: 20000).filter { $0 < 2 * Double.pi - 1e-9 }
            return (try rootsLatex(x, rs), "只列出 [0, 2π) 内的解")
        }
        return (try rootsLatex(x, Numerics.roots(f, in: -100, 100, samples: 40000)), nil)
    }

    static func callNames(_ e: MathExpr) -> Set<String> {
        switch e {
        case .number, .symbol: return []
        case .negate(let a): return callNames(a)
        case .add(let a, let b), .subtract(let a, let b), .multiply(let a, let b), .divide(let a, let b), .power(let a, let b):
            return callNames(a).union(callNames(b))
        case .call(let n, let args): return args.reduce(into: [n]) { $0.formUnion(callNames($1)) }
        case .limit(_, _, _, let b), .integral(_, _, _, let b), .series(_, _, _, let b, _): return callNames(b)
        }
    }

    /// x = 2、x = \pm 2、x_{1} = …,\; x_{2} = …（认不回封闭形式的根写 ≈）。
    static func rootsLatex(_ x: String, _ roots: [Double]) throws -> String {
        guard !roots.isEmpty else { throw Failure.conclusion("方程没有实数解") }
        let forms = roots.map { r -> (String, Bool) in
            if let c = Numerics.closedForm(r, tolerance: 1e-9) { return (c.latex, true) }
            return (approx(r), false)
        }
        if roots.count == 1 { return "\(x) " + (forms[0].1 ? "=" : "\\approx") + " " + forms[0].0 }
        if roots.count == 2, forms.allSatisfy(\.1), abs(roots[0] + roots[1]) <= 1e-9 * max(1, abs(roots[1])), roots[1] > 0 {
            return "\(x) = \\pm " + forms[1].0
        }
        var parts = forms.prefix(6).enumerated().map { i, f in "\(x)_{\(i + 1)} " + (f.1 ? "=" : "\\approx") + " " + f.0 }
        if roots.count > 6 { parts.append("\\ldots") }
        return parts.joined(separator: ",\\; ")
    }

    // MARK: 显示

    static func hint(_ parsed: LatexExpression.Parsed, _ reduced: MathExpr) -> Solution.Hint? {
        guard let t = parsed.target else { return nil }
        switch (t.kind, parsed.expr) {
        case (.integral, .integral(_, let lower?, let upper?, _)):
            guard lower.symbols.isEmpty, upper.symbols.isEmpty else { return nil }
            return .area(function: t.name, from: lower.evaluate([:]), to: upper.evaluate([:]))
        case (.limit, .limit(_, let point, _, _)):
            let a = point.evaluate([:]), y = reduced.evaluate([:])
            guard point.symbols.isEmpty, reduced.symbols.isEmpty, a.isFinite, y.isFinite else { return nil }
            return .point(function: t.name, x: a, y: y)
        default:
            return nil
        }
    }

    /// 按顶层的第一个等号分左右；右边只要到下一个顶层等号（∫… = 学生写的答案 = …）。
    static func splitEquals(_ s: String) -> (lhs: String, rhs: String?) {
        var depth = 0
        var idx = s.startIndex
        while idx < s.endIndex {
            let ch = s[idx]
            if "{([".contains(ch) {
                depth += 1
            } else if "})]".contains(ch) {
                depth -= 1
            } else if ch == "=", depth == 0 {
                let rhs = String(s[s.index(after: idx)...])
                return (String(s[..<idx]).trimmingCharacters(in: .whitespaces),
                        splitEquals(rhs).lhs.trimmingCharacters(in: .whitespaces))
            }
            idx = s.index(after: idx)
        }
        return (s.trimmingCharacters(in: .whitespaces), nil)
    }

    /// 结果写成普通文字（图像上的标签用，不排版）：-\frac{16}{3} → −16/3，\frac{\pi}{4} → π/4，\sqrt{2} → √2。
    public static func plainText(_ latex: String) -> String {
        var s = latex
        func group(_ str: String, from i: String.Index) -> (String, String.Index)? {
            guard i < str.endIndex, str[i] == "{" else { return nil }
            var depth = 0, j = i
            while j < str.endIndex {
                if str[j] == "{" { depth += 1 }
                if str[j] == "}" {
                    depth -= 1
                    if depth == 0 { return (String(str[str.index(after: i)..<j]), str.index(after: j)) }
                }
                j = str.index(after: j)
            }
            return nil
        }
        func wrap(_ t: String) -> String { t.count > 1 && t.contains(where: { "+-− ".contains($0) }) ? "(\(t))" : t }
        // \frac{a}{b}、\sqrt{a}，由里往外
        func innermost() -> Bool {
            var from = s.startIndex
            while let r = s.range(of: "\\frac", range: from..<s.endIndex) {
                if let (a, i) = group(s, from: r.upperBound), let (b, j) = group(s, from: i),
                   !a.contains("\\frac"), !b.contains("\\frac"), !a.contains("\\sqrt"), !b.contains("\\sqrt") {
                    s.replaceSubrange(r.lowerBound..<j, with: wrap(a) + "/" + wrap(b))
                    return true
                }
                from = r.upperBound
            }
            from = s.startIndex
            while let r = s.range(of: "\\sqrt", range: from..<s.endIndex) {
                if let (a, i) = group(s, from: r.upperBound), !a.contains("\\sqrt"), !a.contains("\\frac") {
                    s.replaceSubrange(r.lowerBound..<i, with: "√" + wrap(a))
                    return true
                }
                from = r.upperBound
            }
            return false
        }
        while innermost() {}
        let supers: [Character: Character] = ["0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹", "-": "⁻"]
        while let r = s.range(of: #"\^\{[-0-9]+\}"#, options: .regularExpression) {
            s.replaceSubrange(r, with: String(s[r].dropFirst(2).dropLast().compactMap { supers[$0] }))
        }
        for (a, b) in [("\\left", ""), ("\\right", ""), ("\\pi", "π"), ("\\infty", "∞"), ("\\cdot", "·"), ("\\times", "×"),
                       ("\\pm", "±"), ("\\ln", "ln"), ("\\;", " "), ("\\,", " "), ("{", ""), ("}", ""), ("-", "−")] {
            s = s.replacingOccurrences(of: a, with: b)
        }
        return s.replacingOccurrences(of: "\\", with: "")
    }

    /// 识别器给的 LaTeX 稍微规范一下再排版。
    static func clean(_ s: String) -> String {
        var out = s
        for (a, b) in [("\\dfrac", "\\frac"), ("\\tfrac", "\\frac"), ("\\rightarrow", "\\to"), ("\\limits", ""), ("\\displaystyle", "")] {
            out = out.replacingOccurrences(of: a, with: b)
        }
        return out.trimmingCharacters(in: .whitespaces)
    }

    /// 近似值：6 位有效数字；太大太小写成 a \times 10^{n}。
    static func approx(_ v: Double) -> String {
        let a = abs(v)
        if a != 0, a < 1e-4 || a >= 1e7 {
            let e = Int(Foundation.floor(Foundation.log10(a)))
            var m = String(format: "%.4f", v / Foundation.pow(10, Double(e)))
            while m.hasSuffix("0") { m.removeLast() }
            if m.hasSuffix(".") { m.removeLast() }
            return m + " \\times 10^{\(e)}"
        }
        return String(format: "%.6g", v)
    }
}
