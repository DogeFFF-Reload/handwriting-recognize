import Foundation

// 求导：学生在 f(x) = … 下面写 f'(x)，双击后 App 直接把导函数求出来（不再批改学生写的导数）。
// 符号求导 + 化简 + 写回 LaTeX，规则只覆盖高中课本里的初等函数。

extension MathExpr {
    /// 对 `variable` 求导并化简。x 以外的字母（参数）当常数。
    public func derivative(_ variable: String) -> MathExpr {
        d(variable).simplified(variable)
    }

    private func d(_ v: String) -> MathExpr {
        switch self {
        case .number:
            return .number(0)
        case .symbol(let s):
            return .number(s == v ? 1 : 0)
        case .negate(let a):
            return .negate(a.d(v))
        case .add(let a, let b):
            return .add(a.d(v), b.d(v))
        case .subtract(let a, let b):
            return .subtract(a.d(v), b.d(v))
        case .multiply(let a, let b):
            return .add(.multiply(a.d(v), b), .multiply(a, b.d(v)))
        case .divide(let a, let b):
            if !b.depends(on: v) { return .divide(a.d(v), b) }
            return .divide(.subtract(.multiply(a.d(v), b), .multiply(a, b.d(v))), .power(b, .number(2)))
        case .power(let a, let b):
            if !b.depends(on: v) {
                // (u^n)' = n·u^(n−1)·u'
                return .multiply(.multiply(b, .power(a, .subtract(b, .number(1)))), a.d(v))
            }
            if !a.depends(on: v) {
                // (a^u)' = a^u·ln a·u'；e^u 时 ln e = 1
                let ln: MathExpr = a == .symbol("e") ? .number(1) : .call("ln", [a])
                return .multiply(.multiply(self, ln), b.d(v))
            }
            // u^w = e^(w·ln u)
            return .multiply(self, .add(.multiply(b.d(v), .call("ln", [a])), .divide(.multiply(b, a.d(v)), a)))
        case .call(let name, let args):
            guard let u = args.last else { return .number(.nan) }
            let du = u.d(v)
            let outer: MathExpr
            switch name {
            case "sin": outer = .call("cos", [u])
            case "cos": outer = .negate(.call("sin", [u]))
            case "tan": outer = .divide(.number(1), .power(.call("cos", [u]), .number(2)))
            case "cot": outer = .negate(.divide(.number(1), .power(.call("sin", [u]), .number(2))))
            case "sec": outer = .multiply(.call("sec", [u]), .call("tan", [u]))
            case "csc": outer = .negate(.multiply(.call("csc", [u]), .call("cot", [u])))
            case "arcsin": outer = .divide(.number(1), .call("sqrt", [.subtract(.number(1), .power(u, .number(2)))]))
            case "arccos": outer = .negate(.divide(.number(1), .call("sqrt", [.subtract(.number(1), .power(u, .number(2)))])))
            case "arctan": outer = .divide(.number(1), .add(.number(1), .power(u, .number(2))))
            case "sinh": outer = .call("cosh", [u])
            case "cosh": outer = .call("sinh", [u])
            case "tanh": outer = .divide(.number(1), .power(.call("cosh", [u]), .number(2)))
            case "ln": outer = .divide(.number(1), u)
            case "lg": outer = .divide(.number(1), .multiply(u, .call("ln", [.number(10)])))
            case "log":
                let base: MathExpr = args.count == 2 ? args[0] : .number(10)
                outer = .divide(.number(1), .multiply(u, .call("ln", [base])))
            case "exp": outer = .call("exp", [u])
            case "sqrt": outer = .divide(.number(1), .multiply(.number(2), .call("sqrt", [u])))
            case "root":
                guard args.count == 2 else { return .number(.nan) }
                return MathExpr.power(u, .divide(.number(1), args[0])).d(v)
            case "abs": outer = .divide(u, .call("abs", [u]))
            default: return .number(.nan)
            }
            return .multiply(outer, du)
        }
    }

    func depends(on v: String) -> Bool { symbols.contains(v) }

    var constantValue: Double? {
        if case .number(let n) = self { return n }
        return nil
    }

    // MARK: 化简

    /// 化简：常数折叠、0 和 1 的恒等式、负号往外提、常数因子合并到最前面；
    /// 纯数字系数的多项式整理成按次数降序的标准形式。
    public func simplified(_ v: String = "x") -> MathExpr {
        if let p = polynomial(in: v) {
            return MathExpr.fromPolynomial(p, v)
        }
        let s = simplifyOnce(v)
        let t = s.simplifyOnce(v)
        return t == s ? s : t.simplified(v)
    }

    static func fromPolynomial(_ p: [Int: Double], _ v: String) -> MathExpr {
        let terms = p.filter { abs($0.value) > 1e-12 }.sorted { $0.key > $1.key }
        guard !terms.isEmpty else { return .number(0) }
        var out: MathExpr?
        for (k, c) in terms {
            let mono: MathExpr = k == 0 ? .number(abs(c))
                : k == 1 ? (abs(abs(c) - 1) < 1e-12 ? .symbol(v) : .multiply(.number(abs(c)), .symbol(v)))
                : (abs(abs(c) - 1) < 1e-12 ? .power(.symbol(v), .number(Double(k))) : .multiply(.number(abs(c)), .power(.symbol(v), .number(Double(k)))))
            if let o = out {
                out = c < 0 ? .subtract(o, mono) : .add(o, mono)
            } else {
                out = c < 0 ? .negate(mono) : mono
            }
        }
        return out!
    }

    private func simplifyOnce(_ v: String) -> MathExpr {
        switch self {
        case .number, .symbol:
            return self
        case .negate(let a0):
            let a = a0.simplified(v)
            if let n = a.constantValue { return .number(-n) }
            if case .negate(let inner) = a { return inner }
            return .negate(a)
        case .add(let a0, let b0):
            let a = a0.simplified(v), b = b0.simplified(v)
            if let x = a.constantValue, let y = b.constantValue { return .number(x + y) }
            if a.constantValue == 0 { return b }
            if b.constantValue == 0 { return a }
            if case .negate(let nb) = b { return .subtract(a, nb) }
            if let y = b.constantValue, y < 0 { return .subtract(a, .number(-y)) }
            if case .negate(let na) = a { return .subtract(b, na) }
            return .add(a, b)
        case .subtract(let a0, let b0):
            let a = a0.simplified(v), b = b0.simplified(v)
            if let x = a.constantValue, let y = b.constantValue { return .number(x - y) }
            if b.constantValue == 0 { return a }
            if a.constantValue == 0 { return .negate(b) }
            if case .negate(let nb) = b { return .add(a, nb) }
            if let y = b.constantValue, y < 0 { return .add(a, .number(-y)) }
            if a == b { return .number(0) }
            return .subtract(a, b)
        case .multiply(let a0, let b0):
            let a = a0.simplified(v), b = b0.simplified(v)
            if let x = a.constantValue, let y = b.constantValue { return .number(x * y) }
            if a.constantValue == 0 || b.constantValue == 0 { return .number(0) }
            if a.constantValue == 1 { return b }
            if b.constantValue == 1 { return a }
            if a.constantValue == -1 { return .negate(b) }
            if b.constantValue == -1 { return .negate(a) }
            if case .negate(let na) = a { return .negate(.multiply(na, b)) }
            if case .negate(let nb) = b { return .negate(.multiply(a, nb)) }
            // 常数放前面，并和前面的常数合并：c·(d·u) = (cd)·u
            if b.constantValue != nil, a.constantValue == nil { return .multiply(b, a) }
            if let x = a.constantValue, case .multiply(let c, let rest) = b, let y = c.constantValue {
                return .multiply(.number(x * y), rest)
            }
            if case .multiply(let c, let rest) = a, let x = c.constantValue {
                return .multiply(.number(x), .multiply(rest, b))
            }
            // a·(2·x) → 2·(a·x)：常数因子提到最前（2ax，而不是 a2x）
            if case .multiply(let c, let rest) = b, let y = c.constantValue {
                return .multiply(.number(y), .multiply(a, rest))
            }
            // 多项式因子放在函数前面：cos(x²)·2x → 2x·cos(x²)
            if case .call = a, b.polynomial(in: v) != nil { return .multiply(b, a) }
            // u·u^n = u^(n+1)、u·u = u²
            if a == b { return .power(a, .number(2)) }
            if case .power(let base, let n) = b, base == a, let k = n.constantValue { return .power(a, .number(k + 1)) }
            return .multiply(a, b)
        case .divide(let a0, let b0):
            let a = a0.simplified(v)
            // 分母是 (…)^n 时不展开：-rac{2}{(x-1)^2}，而不是 x^2 - 2x + 1
            let b: MathExpr
            if case .power(let base, let n) = b0, n.constantValue != nil, base.depends(on: v) {
                b = .power(base.simplified(v), n)
            } else {
                b = b0.simplified(v)
            }
            if let x = a.constantValue, let y = b.constantValue, y != 0 { return .number(x / y) }
            if a.constantValue == 0 { return .number(0) }
            if b.constantValue == 1 { return a }
            if case .negate(let na) = a { return .negate(.divide(na, b)) }
            if let x = a.constantValue, x < 0 { return .negate(.divide(.number(-x), b)) }
            if a == b { return .number(1) }
            // (c·u)/d → (c/d)·u
            if let y = b.constantValue, y != 0, case .multiply(let c, let rest) = a, let x = c.constantValue {
                return .multiply(.number(x / y), rest)
            }
            // u / (c·w) 中 u 是常数：留着
            return .divide(a, b)
        case .power(let a0, let b0):
            let a = a0.simplified(v), b = b0.simplified(v)
            if let x = a.constantValue, let y = b.constantValue { return .number(MathExpr.realPower(x, y)) }
            if b.constantValue == 0 { return .number(1) }
            if b.constantValue == 1 { return a }
            if a.constantValue == 1 { return .number(1) }
            if case .power(let base, let inner) = a, let x = inner.constantValue, let y = b.constantValue {
                return .power(base, .number(x * y))
            }
            return .power(a, b)
        case .call(let name, let args):
            let s = args.map { $0.simplified(v) }
            if name == "ln", s.count == 1, s[0] == .symbol("e") { return .number(1) }
            if name == "exp", s.count == 1 { return .power(.symbol("e"), s[0]) }
            if s.allSatisfy({ $0.constantValue != nil }), name != "ln", name != "log", name != "lg" {
                let value = MathExpr.apply(name, s.compactMap(\.constantValue))
                if value.isFinite, abs(value - value.rounded()) < 1e-12 { return .number(value.rounded()) }
            }
            return .call(name, s)
        }
    }

    // MARK: 写回 LaTeX

    /// 写成 LaTeX，括号只在需要时加：2x、x^{2}、\cos x、\cos(2x)、\frac{1}{x}、e^{x}。
    public var latex: String { latex(context: 0) }

    /// context：0 = 和、1 = 积里的因子、2 = 乘方的底。
    private func latex(context: Int) -> String {
        switch self {
        case .number(let n):
            let s = MathExpr.formatNumber(n)
            return n < 0 && context > 0 ? "(\(s))" : s
        case .symbol(let s):
            return s
        case .negate(let a):
            let inner = "-" + a.latex(context: 1)
            return context > 0 ? "(\(inner))" : inner
        case .add(let a, let b):
            let s = a.latex(context: 0) + " + " + b.latex(context: 0)
            return context > 0 ? "(\(s))" : s
        case .subtract(let a, let b):
            let right: String
            switch b {
            case .add, .subtract: right = "(" + b.latex(context: 0) + ")"
            default: right = b.latex(context: 0)
            }
            let s = a.latex(context: 0) + " - " + right
            return context > 0 ? "(\(s))" : s
        case .multiply(let a, let b):
            let left = a.latex(context: 1), right = b.latex(context: 1)
            // 数字后面接数字要用点乘，其余并排（2x、2\cos x、x\sin x、2(x+1)）
            let needsDot = right.first.map { $0.isNumber || $0 == "-" } ?? false
            let s = left + (needsDot ? " \\cdot " : "") + right
            return context == 2 ? "(\(s))" : s
        case .divide(let a, let b):
            let s = "\\frac{\(a.latex(context: 0))}{\(b.latex(context: 0))}"
            return context == 2 ? "(\(s))" : s
        case .power(let a, let b):
            let exp = "{\(b.latex(context: 0))}"
            // sin(u)^2 写成 \sin^{2} u
            if case .call(let name, let args) = a, MathExpr.namedFunctions.contains(name), args.count == 1 {
                return "\\\(name)^\(exp)" + MathExpr.argument(args[0])
            }
            let base: String
            switch a {
            case .number(let n) where n >= 0: base = MathExpr.formatNumber(n)
            case .symbol(let s): base = s
            case .call(let name, _) where name == "sqrt" || name == "abs": base = a.latex(context: 2)
            default: base = "(" + a.latex(context: 0) + ")"
            }
            return base + "^" + exp
        case .call(let name, let args):
            switch name {
            case "sqrt": return "\\sqrt{\(args.last?.latex(context: 0) ?? "")}"
            case "root": return "\\sqrt[\(args[0].latex(context: 0))]{\(args[1].latex(context: 0))}"
            case "abs": return "\\left|\(args.last?.latex(context: 0) ?? "")\\right|"
            case "exp": return "e^{\(args.last?.latex(context: 0) ?? "")}"
            case "log" where args.count == 2: return "\\log_{\(args[0].latex(context: 0))}" + MathExpr.argument(args[1])
            default: return "\\\(name)" + MathExpr.argument(args.last ?? .number(.nan))
            }
        }
    }

    static let namedFunctions: Set<String> = ["sin", "cos", "tan", "cot", "sec", "csc", "arcsin", "arccos", "arctan",
                                               "sinh", "cosh", "tanh", "ln", "lg", "log"]

    /// 函数名后面的参数：单个字母或数字不加括号（\sin x），其余加（\sin(2x)）。
    static func argument(_ u: MathExpr) -> String {
        switch u {
        case .symbol(let s): return " " + s
        case .number(let n) where n >= 0: return " " + formatNumber(n)
        default: return "(" + u.latex(context: 0) + ")"
        }
    }

    /// 数字：整数照写；分母不超过 12 的分数写成 \frac；π 写成 \pi；其余保留 4 位有效数字。
    static func formatNumber(_ n: Double) -> String {
        guard n.isFinite else { return "\\text{?}" }
        if abs(n - n.rounded()) < 1e-9 { return String(Int(n.rounded())) }
        if abs(abs(n) - Double.pi) < 1e-12 { return n < 0 ? "-\\pi" : "\\pi" }
        for q in 2...12 {
            let p = n * Double(q)
            if abs(p - p.rounded()) < 1e-9 {
                let pi = Int(p.rounded())
                return (pi < 0 ? "-" : "") + "\\frac{\(abs(pi))}{\(q)}"
            }
        }
        var s = String(format: "%.4g", n)
        if s.contains("e") { s = String(format: "%.4f", n) }
        return s
    }
}

/// 学生写在函数下面的「f'(x)」「f''(x)」「y'」「f'(2)」：要对哪个函数求几阶导，在哪一点取值。
/// 等号后面写了什么都不看（不再批改，直接求出来）。
public struct DerivativeRequest: Equatable {
    /// 函数名：f、g、y……
    public var name: String
    /// 几阶导：f' 是 1，f'' 是 2。
    public var order: Int
    /// 括号里写的数（f'(2)）：有就在这一点取值；写的是自变量或没写括号时为 nil。
    public var point: Double?
    /// 括号里写的自变量（f'(x) 里的 x）；没写括号时为 nil。
    public var variable: String?

    public init(name: String, order: Int, point: Double? = nil, variable: String? = nil) {
        self.name = name
        self.order = order
        self.point = point
        self.variable = variable
    }

    /// 认不出就返回 nil（例如这一行其实是 f(x) = …）。
    public static func parse(_ latex: String) -> DerivativeRequest? {
        var s = latex
        for (a, b) in [("$", ""), ("\\left", ""), ("\\right", ""), ("\\displaystyle", ""), ("\\,", ""), ("\\;", ""),
                       ("\\!", ""), ("\\ ", ""), ("\\prime", "'"), ("’", "'"), ("′", "'"), ("″", "''"), ("−", "-")] {
            s = s.replacingOccurrences(of: a, with: b)
        }
        s = s.filter { !$0.isWhitespace }
        // f^{''}(x)、f^'(x) → f''(x)
        while let r = s.range(of: #"\^\{('+)\}"#, options: .regularExpression) {
            s.replaceSubrange(r, with: s[r].filter { $0 == "'" })
        }
        s = s.replacingOccurrences(of: "^'", with: "'")
        let lhs = s.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? s
        guard let m = lhs.range(of: #"^[A-Za-z]'{1,3}(\([^()]*\))?$"#, options: .regularExpression), m == lhs.startIndex..<lhs.endIndex else {
            return nil
        }
        let name = String(lhs.first!)
        let order = lhs.filter { $0 == "'" }.count
        var request = DerivativeRequest(name: name, order: order)
        if let open = lhs.firstIndex(of: "("), let close = lhs.lastIndex(of: ")") {
            let inside = String(lhs[lhs.index(after: open)..<close])
            if inside.count == 1, inside.first!.isLetter {
                request.variable = inside
            } else if let d = try? FunctionDefinition.parse(inside), d.parameters.isEmpty, !d.body.symbols.contains("x"),
                      !d.body.symbols.contains(d.variable) {
                request.point = d.body.evaluate([:])
            } else if !inside.isEmpty {
                return nil
            }
        }
        return request
    }

    /// 写回 LaTeX 的左边：f'(x)、f''(x)、f'(2)、y'。
    public func lhsLatex(variable: String) -> String {
        let primes = String(repeating: "'", count: order)
        if let p = point { return "\(name)\(primes)(\(MathExpr.formatNumber(p)))" }
        if name == "y", self.variable == nil { return "y\(primes)" }
        return "\(name)\(primes)(\(self.variable ?? variable))"
    }
}
