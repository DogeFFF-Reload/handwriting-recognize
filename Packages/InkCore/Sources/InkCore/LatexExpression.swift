import Foundation

// 手写数学式（MyScript / Qwen 给的 LaTeX）→ 能求值的表达式，给函数图像和「求解」用。
//
// 认的 LaTeX：数字、x、π、e、∞、+ − × ÷、^、\frac、\sqrt、括号、|x|、n!、
// \sin \cos \tan \ln \log \exp 等，隐式乘法（3x、2\sin x、(x+1)(x-1)），
// 以及 \lim_{x\to a}、\int（定积分 / 不定积分）、\sum / \prod、\frac{d}{dx}，
// 和已经写过的函数的引用：f(x)、f(2)、f'(x)。
// x 以外的单个字母（a、b、k…）当作参数，图像上给它们滑条（GeoGebra 的做法）；e 是自然常数。

public indirect enum MathExpr: Equatable {
    case number(Double)
    /// 自变量或参数。
    case symbol(String)
    case negate(MathExpr)
    case add(MathExpr, MathExpr)
    case subtract(MathExpr, MathExpr)
    case multiply(MathExpr, MathExpr)
    case divide(MathExpr, MathExpr)
    case power(MathExpr, MathExpr)
    /// sin、cos、ln、sqrt、abs、factorial……；带底的对数是 call("log", [底, 真数])，n 次根是 call("root", [n, 被开方数])。
    case call(String, [MathExpr])
    /// 极限：变量、趋向的点（可以是 ±∞）、方向（0 两侧、1 从右、-1 从左）、被求极限的式子。
    case limit(String, MathExpr, Int, MathExpr)
    /// 积分：积分变量、下限、上限（不定积分两个都是 nil）、被积函数。
    case integral(String, MathExpr?, MathExpr?, MathExpr)
    /// 求和 / 连乘：变量、下界、上界（可以是 ∞）、通项、是不是连乘。
    case series(String, MathExpr, MathExpr, MathExpr, Bool)

    /// 自然常数 e（Windows 上没有 M_E）。
    public static let euler = 2.718281828459045
    /// 写成符号的常数：e 和 π（算出来的 π/4、e − 1 这样的结果里用；手写的 \pi 解析时直接是数）。
    static let constants: Set<String> = ["e", "π"]
    public static let e = MathExpr.symbol("e")
    public static let pi = MathExpr.symbol("π")

    /// 求值。`values` 里放自变量和参数；没给值的参数按 1 算。极限、积分、求和按数值方法算。
    public func evaluate(_ values: [String: Double]) -> Double {
        switch self {
        case .number(let v): return v
        case .symbol(let s):
            if let v = values[s] { return v }
            return s == "e" ? MathExpr.euler : s == "π" ? Double.pi : 1
        case .negate(let a): return -a.evaluate(values)
        case .add(let a, let b): return a.evaluate(values) + b.evaluate(values)
        case .subtract(let a, let b): return a.evaluate(values) - b.evaluate(values)
        case .multiply(let a, let b): return a.evaluate(values) * b.evaluate(values)
        case .divide(let a, let b): return a.evaluate(values) / b.evaluate(values)
        case .power(let a, let b): return MathExpr.realPower(a.evaluate(values), b.evaluate(values))
        case .call(let name, let args):
            let v = args.map { $0.evaluate(values) }
            return MathExpr.apply(name, v)
        case .limit(let v, let point, let side, let body):
            let f = MathExpr.closure(body, v, values)
            return Numerics.limit(f, at: point.evaluate(values), side: side).value ?? .nan
        case .integral(let v, let lower, let upper, let body):
            guard let lower, let upper else { return .nan }
            return Numerics.integrate(MathExpr.closure(body, v, values), lower.evaluate(values), upper.evaluate(values)) ?? .nan
        case .series(let v, let lower, let upper, let body, let product):
            return Numerics.series(MathExpr.closure(body, v, values), from: lower.evaluate(values), to: upper.evaluate(values),
                                   product: product).value ?? .nan
        }
    }

    static func closure(_ body: MathExpr, _ v: String, _ values: [String: Double]) -> (Double) -> Double {
        { t in
            var env = values
            env[v] = t
            return body.evaluate(env)
        }
    }

    /// 出现过的自由符号（不含 e、π；极限、积分、求和里约束住的变量不算）。
    public var symbols: Set<String> {
        switch self {
        case .number: return []
        case .symbol(let s): return MathExpr.constants.contains(s) ? [] : [s]
        case .negate(let a): return a.symbols
        case .add(let a, let b), .subtract(let a, let b), .multiply(let a, let b), .divide(let a, let b), .power(let a, let b):
            return a.symbols.union(b.symbols)
        case .call(_, let args): return args.reduce(into: Set<String>()) { $0.formUnion($1.symbols) }
        case .limit(let v, let point, _, let body):
            return body.symbols.subtracting([v]).union(point.symbols)
        case .integral(let v, let lower, let upper, let body):
            var s = body.symbols
            if lower != nil || upper != nil { s.remove(v) }
            return s.union(lower?.symbols ?? []).union(upper?.symbols ?? [])
        case .series(let v, let lower, let upper, let body, _):
            return body.symbols.subtracting([v]).union(lower.symbols).union(upper.symbols)
        }
    }

    /// 有没有极限、积分、求和。
    public var containsBigOperator: Bool {
        switch self {
        case .number, .symbol: return false
        case .negate(let a): return a.containsBigOperator
        case .add(let a, let b), .subtract(let a, let b), .multiply(let a, let b), .divide(let a, let b), .power(let a, let b):
            return a.containsBigOperator || b.containsBigOperator
        case .call(_, let args): return args.contains { $0.containsBigOperator }
        case .limit, .integral, .series: return true
        }
    }

    /// 把符号 `name` 换成 `e`（被约束住的同名变量不换）。
    public func substituting(_ name: String, with e: MathExpr) -> MathExpr {
        func s(_ x: MathExpr) -> MathExpr { x.substituting(name, with: e) }
        switch self {
        case .number: return self
        case .symbol(let n): return n == name ? e : self
        case .negate(let a): return .negate(s(a))
        case .add(let a, let b): return .add(s(a), s(b))
        case .subtract(let a, let b): return .subtract(s(a), s(b))
        case .multiply(let a, let b): return .multiply(s(a), s(b))
        case .divide(let a, let b): return .divide(s(a), s(b))
        case .power(let a, let b): return .power(s(a), s(b))
        case .call(let n, let args): return .call(n, args.map(s))
        case .limit(let v, let point, let side, let body):
            return .limit(v, s(point), side, v == name ? body : s(body))
        case .integral(let v, let lower, let upper, let body):
            let bound = lower != nil || upper != nil
            return .integral(v, lower.map(s), upper.map(s), bound && v == name ? body : s(body))
        case .series(let v, let lower, let upper, let body, let product):
            return .series(v, s(lower), s(upper), v == name ? body : s(body), product)
        }
    }

    /// 只含数字系数时展开成多项式（次数 → 系数）；不是多项式、或带参数时返回 nil。
    public func polynomial(in variable: String) -> [Int: Double]? {
        func clean(_ p: [Int: Double]) -> [Int: Double] { p.filter { abs($0.value) > 1e-12 } }
        switch self {
        case .number(let v): return v.isFinite ? clean([0: v]) : nil
        case .symbol(let s):
            // e 不算数字系数：e^x、ex 留成式子，求导和写回 LaTeX 时 e 还是 e
            return s == variable ? [1: 1] : nil
        case .negate(let a): return a.polynomial(in: variable).map { $0.mapValues { -$0 } }
        case .add(let a, let b), .subtract(let a, let b):
            guard let p = a.polynomial(in: variable), var q = b.polynomial(in: variable) else { return nil }
            if case .subtract = self { q = q.mapValues { -$0 } }
            return clean(p.merging(q, uniquingKeysWith: +))
        case .multiply(let a, let b):
            guard let p = a.polynomial(in: variable), let q = b.polynomial(in: variable) else { return nil }
            var r: [Int: Double] = [:]
            for (i, c) in p { for (j, d) in q { r[i + j, default: 0] += c * d } }
            guard (r.keys.max() ?? 0) <= 12 else { return nil }
            return clean(r)
        case .divide(let a, let b):
            guard let p = a.polynomial(in: variable), let q = b.polynomial(in: variable),
                  q.keys.allSatisfy({ $0 == 0 }), let d = q[0], abs(d) > 1e-12 else { return nil }
            return clean(p.mapValues { $0 / d })
        case .power(let a, let b):
            guard let base = a.polynomial(in: variable), let e = b.polynomial(in: variable),
                  e.keys.allSatisfy({ $0 == 0 }) else { return nil }
            let n = e[0] ?? 0
            guard n >= 0, n <= 12, n == n.rounded() else { return nil }
            var r: [Int: Double] = [0: 1]
            for _ in 0..<Int(n) {
                var next: [Int: Double] = [:]
                for (i, c) in r { for (j, d) in base { next[i + j, default: 0] += c * d } }
                r = next
            }
            guard (r.keys.max() ?? 0) <= 12 else { return nil }
            return clean(r)
        case .call, .limit, .integral, .series: return nil
        }
    }

    static func apply(_ name: String, _ v: [Double]) -> Double {
        guard let x = v.last else { return .nan }
        switch name {
        case "sin": return sin(x)
        case "cos": return cos(x)
        case "tan": return tan(x)
        case "cot": return 1 / tan(x)
        case "sec": return 1 / cos(x)
        case "csc": return 1 / sin(x)
        case "arcsin": return asin(x)
        case "arccos": return acos(x)
        case "arctan": return atan(x)
        case "sinh": return sinh(x)
        case "cosh": return cosh(x)
        case "tanh": return tanh(x)
        case "ln": return log(x)
        case "lg": return log10(x)
        case "log": return v.count == 2 ? log(x) / log(v[0]) : log10(x)
        case "exp": return exp(x)
        case "sqrt": return sqrt(x)
        case "root":
            guard v.count == 2 else { return .nan }
            return realPower(x, 1 / v[0])
        case "abs": return abs(x)
        case "factorial":
            if x < 0, x == x.rounded() { return .nan }
            return tgamma(x + 1)
        default: return .nan
        }
    }

    /// 实数范围内的乘方：负数开奇次方（如 x^{1/3}）照样有值。
    static func realPower(_ a: Double, _ b: Double) -> Double {
        if a >= 0 || b == b.rounded() { return Foundation.pow(a, b) }
        for q in stride(from: 3, through: 9, by: 2) {
            let p = b * Double(q)
            if abs(p - p.rounded()) < 1e-9 {
                let r = Foundation.pow(-a, b)
                return Int(p.rounded()) % 2 == 0 ? r : -r
            }
        }
        return .nan
    }
}

/// 一条可以作图的函数：f(x) = …、y = …，或者只写了右边。
public struct FunctionDefinition: Equatable {
    /// 函数名：f、g、y……只写了右边时是 f。
    public var name: String
    /// 自变量，一般是 x；写成 f(t) = … 时是 t。
    public var variable: String
    public var body: MathExpr
    /// 自变量以外的字母，按字母序（滑条用）。
    public var parameters: [String]

    public init(name: String, variable: String, body: MathExpr) {
        self.name = name
        self.variable = variable
        self.body = body
        parameters = body.symbols.subtracting([variable]).sorted()
    }

    /// 纯数字系数的多项式（次数 → 系数）；带参数或不是多项式时为 nil。
    public var polynomial: [Int: Double]? {
        parameters.isEmpty ? body.polynomial(in: variable) : nil
    }

    public func evaluate(_ x: Double, parameters values: [String: Double] = [:]) -> Double {
        var env = values
        env[variable] = x
        return body.evaluate(env)
    }

    public enum ParseError: Error, Equatable {
        case empty
        case notAFunction(String)
        case unexpected(String)
    }

    /// `functions`：已经写过的函数，右边出现 f(x)、f'(x) 时直接代进去（g(x) = f(x) + 1）。
    public static func parse(_ latex: String, functions: [String: FunctionDefinition] = [:]) throws -> FunctionDefinition {
        let tokens = try LatexExpression.tokenize(firstLine(latex))
        guard !tokens.isEmpty else { throw ParseError.empty }
        guard let eq = LatexExpression.topLevelEquals(tokens) else {
            var p = LatexExpression(tokens, functions: functions)
            let body = try plottable(p.parseAll())
            let v = body.symbols.contains("x") || !body.symbols.contains("t") ? "x" : "t"
            return FunctionDefinition(name: "f", variable: v, body: body)
        }
        let lhs = Array(tokens[..<eq])
        var rhs = Array(tokens[(eq + 1)...])
        if let second = LatexExpression.topLevelEquals(rhs) { rhs = Array(rhs[..<second]) }   // f(x) = … = …：只要第一段
        guard !rhs.isEmpty else { throw ParseError.empty }
        guard let header = LatexExpression.functionHeader(lhs) else {
            throw ParseError.notAFunction(lhs.map(\.text).joined())
        }
        var p = LatexExpression(rhs, functions: functions.filter { $0.key != header.name })
        return FunctionDefinition(name: header.name, variable: header.variable, body: try plottable(p.parseAll()))
    }

    /// 极限、积分、求和要「求解」，不在这里作图。
    private static func plottable(_ body: MathExpr) throws -> MathExpr {
        guard !body.containsBigOperator else { throw ParseError.unexpected("\\lim / \\int / \\sum（选「求解」）") }
        return body
    }

    /// 识别器给的多行结果（\\ 换行、\begin{aligned}…）只取第一行。
    static func firstLine(_ latex: String) -> String {
        var s = latex
        while let r = s.range(of: #"\\(begin|end)\{[a-z*]+\}(\{[a-z]*\})?"#, options: .regularExpression) {
            s.replaceSubrange(r, with: " ")
        }
        s = s.replacingOccurrences(of: "&", with: "")
        let lines = s.components(separatedBy: "\\\\").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return lines.first { !$0.isEmpty } ?? ""
    }
}

/// 递归下降解析。优先级：加减 < 乘除（含隐式乘法）< 正负号 < 乘方（右结合）< 阶乘。
/// \lim 和 \sum 的作用范围到下一个加减号为止（和乘除同级）；\int 一直到 dx。
struct LatexExpression {
    enum Token: Equatable {
        case number(String)
        case symbol(String)
        case command(String)        // 不带反斜杠：sin、frac、sqrt、pi、lim、int……
        case op(Character)          // + - * / ^ _
        case open(Character)        // ( { [
        case close(Character)       // ) } ]
        case bar                    // |
        case equals
        case prime                  // '
        case arrow                  // \to
        case bang                   // !

        var text: String {
            switch self {
            case .number(let s), .symbol(let s): return s
            case .command(let s): return "\\" + s
            case .op(let c), .open(let c), .close(let c): return String(c)
            case .bar: return "|"
            case .equals: return "="
            case .prime: return "'"
            case .arrow: return "→"
            case .bang: return "!"
            }
        }
    }

    /// 整句是不是「对一条已有函数」求积分 / 极限 / 和，例如 \int_0^2 f(x)dx：图像上要标出来。
    struct Target: Equatable {
        enum Kind: Equatable { case integral, limit, series }
        var name: String
        var kind: Kind
    }

    static let functions: Set<String> = ["sin", "cos", "tan", "cot", "sec", "csc", "arcsin", "arccos", "arctan",
                                         "sinh", "cosh", "tanh", "ln", "lg", "log", "exp"]
    static let bigOperators: Set<String> = ["lim", "int", "sum", "prod"]

    var tokens: [Token]
    var i = 0
    var absDepth = 0
    /// 正在读 \int 的被积函数：遇到 dx 就停。
    var differentialDepth = 0
    /// 已经写过的函数：f(x)、f'(2) 直接代进去。
    let defined: [String: FunctionDefinition]
    private(set) var references: Set<String> = []
    private(set) var target: Target?
    /// 用到了 \frac{d}{dx}。
    private(set) var usesDerivative = false

    init(_ tokens: [Token], functions: [String: FunctionDefinition] = [:]) {
        self.tokens = tokens
        self.defined = functions
    }

    struct Parsed {
        var expr: MathExpr
        var references: Set<String>
        var target: Target?
        var usesDerivative: Bool
        /// 有没有要「算」的东西：极限、积分、求和、d/dx。
        var hasOperation: Bool { usesDerivative || expr.containsBigOperator }
    }

    /// 解析一整句（等号左边或一个完整的式子）。
    static func parseExpression(_ latex: String, functions: [String: FunctionDefinition]) throws -> Parsed {
        let tokens = try tokenize(latex)
        guard !tokens.isEmpty else { throw FunctionDefinition.ParseError.empty }
        var p = LatexExpression(tokens, functions: functions)
        let e = try p.parseAll()
        return Parsed(expr: e, references: p.references, target: p.target, usesDerivative: p.usesDerivative)
    }

    /// 顶层（不在括号里）的第一个等号。
    static func topLevelEquals(_ tokens: [Token]) -> Int? {
        var depth = 0
        for (i, t) in tokens.enumerated() {
            switch t {
            case .open: depth += 1
            case .close: depth -= 1
            case .equals where depth == 0: return i
            default: break
            }
        }
        return nil
    }

    /// 「f(x)」「y」这种函数的左边。
    static func functionHeader(_ lhs: [Token]) -> (name: String, variable: String)? {
        func letter(_ t: Token) -> String? {
            if case .symbol(let s) = t { return s }
            return nil
        }
        if lhs.count == 1, let n = letter(lhs[0]), n != "x" { return (n, "x") }
        if lhs.count == 4, let n = letter(lhs[0]), lhs[1] == .open("("), let v = letter(lhs[2]), case .close = lhs[3] {
            return (n, v)
        }
        return nil
    }

    // MARK: 词法

    static func tokenize(_ latex: String) throws -> [Token] {
        var s = latex
        let pairs: [(String, String)] = [
            // 先换掉箭头：\rightarrow 里有 \right
            ("\\longrightarrow", "\\to "), ("\\rightarrow", "\\to "), ("\\Rightarrow", "\\to "),
            ("$", ""), ("\\displaystyle", ""), ("\\left", ""), ("\\right", ""), ("\\bigl", ""), ("\\bigr", ""),
            ("\\Big", ""), ("\\big", ""), ("\\limits", ""), ("\\nolimits", ""),
            ("\\,", ""), ("\\;", ""), ("\\:", ""), ("\\!", ""), ("\\ ", ""), ("~", ""),
            ("\\dfrac", "\\frac"), ("\\tfrac", "\\frac"), ("\\cdot", "*"), ("\\times", "*"), ("\\ast", "*"), ("\\div", "/"),
            ("\\lvert", "|"), ("\\rvert", "|"), ("\\vert", "|"), ("\\mid", "|"), ("\\{", "("), ("\\}", ")"),
            ("\\lbrace", "("), ("\\rbrace", ")"), ("\\lbrack", "("), ("\\rbrack", ")"),
            ("−", "-"), ("–", "-"), ("×", "*"), ("·", "*"), ("⋅", "*"), ("÷", "/"), ("π", "\\pi "), ("∞", "\\infty "),
            ("²", "^2"), ("³", "^3"), ("√", "\\sqrt "), ("’", "'"), ("′", "'"), ("″", "''"), ("∫", "\\int "), ("∑", "\\sum "),
        ]
        for (a, b) in pairs { s = s.replacingOccurrences(of: a, with: b) }
        // f^{\prime}(x)、f^{\prime\prime}(x) → f'(x)、f''(x)
        while let r = s.range(of: #"\^\{\s*(\\prime\s*)+\}"#, options: .regularExpression) {
            let n = s[r].components(separatedBy: "\\prime").count - 1
            s.replaceSubrange(r, with: String(repeating: "'", count: n))
        }
        s = s.replacingOccurrences(of: "^\\prime", with: "'").replacingOccurrences(of: "\\prime", with: "'")

        var out: [Token] = []
        let chars = Array(s)
        var k = 0
        let autoNames = (functions.union(["lim"])).sorted { $0.count > $1.count }
        while k < chars.count {
            let c = chars[k]
            if c.isWhitespace { k += 1; continue }
            if c.isNumber || (c == "." && k + 1 < chars.count && chars[k + 1].isNumber) {
                var j = k
                var dot = false
                while j < chars.count, chars[j].isNumber || (chars[j] == "." && !dot) {
                    if chars[j] == "." { dot = true }
                    j += 1
                }
                out.append(.number(String(chars[k..<j])))
                k = j
                continue
            }
            if c == "\\" {
                var j = k + 1
                while j < chars.count, chars[j].isLetter { j += 1 }
                let name = String(chars[(k + 1)..<j])
                guard !name.isEmpty else { throw FunctionDefinition.ParseError.unexpected("\\") }
                k = j
                // \operatorname{sin}、\mathrm{e}、\mathrm{d}、\text{…}：取花括号里的字，当成函数名或字母
                if ["operatorname", "mathrm", "mathit", "text", "textrm", "mathbf"].contains(name) {
                    guard k < chars.count, chars[k] == "{", let end = chars[k...].firstIndex(of: "}") else {
                        throw FunctionDefinition.ParseError.unexpected("\\" + name)
                    }
                    let word = String(chars[(k + 1)..<end]).filter { !$0.isWhitespace }
                    k = end + 1
                    if word.count == 1 { out.append(.symbol(word)) }
                    else if functions.contains(word) || bigOperators.contains(word) { out.append(.command(word)) }
                    else if !word.isEmpty { throw FunctionDefinition.ParseError.unexpected(word) }
                    continue
                }
                if ["to", "rightarrow", "longrightarrow", "mapsto", "Rightarrow"].contains(name) {
                    out.append(.arrow)
                } else {
                    out.append(.command(name))
                }
                continue
            }
            if c.isLetter {
                // 识别器偶尔把 \sin、\lim 写成普通字母：连着的函数名照样认
                if let f = autoNames.first(where: { name in
                    k + name.count <= chars.count && String(chars[k..<(k + name.count)]) == name
                }), f.count > 1 {
                    out.append(.command(f))
                    k += f.count
                    continue
                }
                out.append(.symbol(String(c)))
                k += 1
                continue
            }
            switch c {
            case "+", "-", "*", "/", "^", "_": out.append(.op(c))
            case "(", "{", "[": out.append(.open(c))
            case ")", "}", "]": out.append(.close(c))
            case "|": out.append(.bar)
            case "=": out.append(.equals)
            case "'": out.append(.prime)
            case "!": out.append(.bang)
            case "→": out.append(.arrow)
            default: throw FunctionDefinition.ParseError.unexpected(String(c))
            }
            k += 1
        }
        return out
    }

    // MARK: 语法

    mutating func parseAll() throws -> MathExpr {
        let e = try parseSum()
        guard i == tokens.count else { throw FunctionDefinition.ParseError.unexpected(tokens[i].text) }
        return e
    }

    private var peek: Token? { i < tokens.count ? tokens[i] : nil }

    private func token(at k: Int) -> Token? { k < tokens.count ? tokens[k] : nil }

    private mutating func next() -> Token? {
        defer { i += 1 }
        return peek
    }

    private mutating func expect(_ t: Token) throws {
        guard peek == t else { throw FunctionDefinition.ParseError.unexpected(peek?.text ?? "结尾") }
        i += 1
    }

    private func unexpected(_ s: String) -> FunctionDefinition.ParseError { .unexpected(s) }

    private mutating func parseSum() throws -> MathExpr {
        var e = try parseProduct()
        while let t = peek {
            if t == .op("+") { i += 1; e = .add(e, try parseProduct()) }
            else if t == .op("-") { i += 1; e = .subtract(e, try parseProduct()) }
            else { break }
        }
        return e
    }

    private mutating func parseProduct() throws -> MathExpr {
        var e = try parseSigned()
        while let t = peek {
            if t == .op("*") { i += 1; e = .multiply(e, try parseSigned()) }
            else if t == .op("/") { i += 1; e = .divide(e, try parseSigned()) }
            else if let joined = joinSplitNumber(e) { e = joined }
            else if startsFactor(t) { e = .multiply(e, try parsePower()) }   // 3x、2\sin x、(x+1)(x-1)
            else { break }
        }
        return e
    }

    /// 识别器把 10 拆成相邻数字（^{1 0}、^{1}{0}）。隐式相乘会得到 0，求和从 1 到 0 就是空和。
    /// 只拼纯整数，2n、2{x} 仍是乘法。x^23 走的是上标单字符规则，这里碰不到。
    private mutating func joinSplitNumber(_ e: MathExpr) -> MathExpr? {
        guard case .number(let n) = e, n.isFinite, n == n.rounded(), abs(n) < 1e12 else { return nil }
        let sign = n < 0 ? -1.0 : 1.0
        var digits = String(Int(abs(n).rounded()))
        let start = i
        while let more = peekSplitDigits() {
            digits += more.text
            i = more.end
        }
        guard i != start, let v = Double(digits) else { i = start; return nil }
        return .number(sign * v)
    }

    private func peekSplitDigits() -> (text: String, end: Int)? {
        if case .number(let s)? = peek, isDigitRun(s) { return (s, i + 1) }
        return bracedDigits(at: i)
    }

    private func bracedDigits(at start: Int) -> (text: String, end: Int)? {
        guard case .open? = token(at: start) else { return nil }
        var k = start + 1
        var text = ""
        while k < tokens.count {
            switch tokens[k] {
            case .number(let s) where isDigitRun(s):
                text += s
                k += 1
            case .open:
                guard let inner = bracedDigits(at: k) else { return nil }
                text += inner.text
                k = inner.end
            case .close:
                guard !text.isEmpty else { return nil }
                return (text, k + 1)
            default:
                return nil
            }
        }
        return nil
    }

    private func isDigitRun(_ s: String) -> Bool {
        !s.isEmpty && !s.contains(".") && s.allSatisfy { $0.isNumber }
    }

    private mutating func parseSigned() throws -> MathExpr {
        if peek == .op("-") { i += 1; return .negate(try parseSigned()) }
        if peek == .op("+") { i += 1; return try parseSigned() }
        return try parsePower()
    }

    private mutating func parsePower() throws -> MathExpr {
        var base = try parsePrimary()
        while peek == .bang {
            i += 1
            base = .call("factorial", [base])
        }
        guard peek == .op("^") else { return base }
        i += 1
        let exp = try parseScript()
        // 右结合：a^b^c = a^(b^c)
        if peek == .op("^") {
            i += 1
            return .power(base, .power(exp, try parseScript()))
        }
        return .power(base, exp)
    }

    /// 求和、积分的上下界。不带花括号时把整个数字读完（^10 是 10，不是 1 再乘 0）。
    /// 花括号里的数字不向外吞，\sum_{k=0}^{10}2^{k} 的 2 仍是通项。
    private mutating func parseBound() throws -> MathExpr {
        try parseScript(wholeNumber: true)
    }

    /// ^ 或 _ 后面的部分：{…} 整组；不带括号时按 LaTeX 只取一个字符（x^23 是 x² · 3）。
    private mutating func parseScript(wholeNumber: Bool = false) throws -> MathExpr {
        guard let t = peek else { throw unexpected("结尾") }
        switch t {
        case .open:
            return try parseGroup()
        case .number(let s):
            if !wholeNumber, s.count > 1, !s.contains(".") {
                tokens[i] = .number(String(s.dropFirst()))
                return .number(Double(String(s.first!))!)
            }
            i += 1
            return .number(Double(s) ?? .nan)
        case .op("-"):
            i += 1   // x^-1：不合 LaTeX，识别器偶尔这么给
            return .negate(try parseScript())
        default:
            return try parsePrimary()
        }
    }

    private mutating func parseGroup() throws -> MathExpr {
        guard case .open(let o) = next() else { throw unexpected(tokens[i - 1].text) }
        let saved = absDepth, savedD = differentialDepth
        absDepth = 0
        differentialDepth = 0
        let e = try parseSum()
        absDepth = saved
        differentialDepth = savedD
        // 手写识别偶尔给出 ( … } 这种配不上的括号：只要是右括号就收
        guard case .close = peek else { throw unexpected(peek?.text ?? "缺少与 \(o) 对应的右括号") }
        i += 1
        return e
    }

    private func startsFactor(_ t: Token) -> Bool {
        // \int … dx：读被积函数时，d 后面跟着字母就是微分，停
        if differentialDepth > 0, t == .symbol("d"), case .symbol? = token(at: i + 1) { return false }
        switch t {
        case .number, .symbol, .open: return true
        case .command(let c): return c != "right"
        case .bar: return absDepth == 0
        default: return false
        }
    }

    private mutating func parsePrimary() throws -> MathExpr {
        guard let t = peek else { throw unexpected("结尾") }
        switch t {
        case .number(let s):
            i += 1
            guard let v = Double(s) else { throw unexpected(s) }
            return .number(v)
        case .symbol(let s):
            i += 1
            // 已经写过的函数：f(x)、f(2)、f'(x)、y' 直接代进去
            if let def = defined[s], peek == .open("(") || peek == .prime {
                var order = 0
                while peek == .prime { i += 1; order += 1 }
                let arg: MathExpr = peek == .open("(") ? try parseGroup() : .symbol(def.variable)
                references.insert(s)
                var body = def.body
                for _ in 0..<order { body = body.derivative(def.variable) }
                return body.substituting(def.variable, with: arg)
            }
            if peek == .prime { throw unexpected("\(s)'（上面还没有写 \(s)(x) = …）") }
            return .symbol(s)
        case .open:
            return try parseGroup()
        case .bar:
            i += 1
            absDepth += 1
            let e = try parseSum()
            absDepth -= 1
            try expect(.bar)
            return .call("abs", [e])
        case .command(let name):
            i += 1
            return try parseCommand(name)
        default:
            throw unexpected(t.text)
        }
    }

    private mutating func parseCommand(_ name: String) throws -> MathExpr {
        switch name {
        case "pi": return .number(Double.pi)
        case "infty": return .number(.infinity)
        case "lim": return try parseLimit()
        case "int": return try parseIntegral()
        case "sum", "prod": return try parseSeries(product: name == "prod")
        case "frac":
            if let op = try parseDerivativeOperator() { return op }
            let a = try parseScriptOrGroup()
            let b = try parseScriptOrGroup()
            return .divide(a, b)
        case "sqrt":
            if peek == .open("[") {
                let n = try parseGroup()
                return .call("root", [n, try parseScriptOrGroup()])
            }
            return .call("sqrt", [try parseScriptOrGroup()])
        case _ where Self.functions.contains(name):
            var power: MathExpr?
            var base: MathExpr?
            // \sin^2 x、\log_2 x、\log_{10}(x)
            while peek == .op("^") || peek == .op("_") {
                let isPower = peek == .op("^")
                i += 1
                if isPower { power = try parseScript() } else { base = try parseScript() }
            }
            let arg = try parseFunctionArgument()
            var call: MathExpr = base.map { .call("log", [$0, arg]) } ?? .call(name, [arg])
            if let p = power {
                // \sin^{-1} x 是反函数
                if p == .negate(.number(1)), ["sin", "cos", "tan"].contains(name) {
                    call = .call("arc" + name, [arg])
                } else {
                    call = .power(call, p)
                }
            }
            return call
        default:
            throw unexpected("\\" + name)
        }
    }

    /// \frac、\sqrt 的参数：{…} 整组，否则一个字符。
    private mutating func parseScriptOrGroup() throws -> MathExpr {
        if case .open = peek { return try parseGroup() }
        return try parseScript()
    }

    /// 函数的参数：(…) 整组；没括号时一直吃到加减号或下一个函数（\sin 2x → sin(2x)，\sin x\cos x → sin x · cos x）。
    private mutating func parseFunctionArgument() throws -> MathExpr {
        if case .open = peek { return try parseGroup() }
        var e = try parseSigned()
        while let t = peek, startsFactor(t) {
            if case .command(let c) = t, Self.functions.contains(c) || Self.bigOperators.contains(c) { break }
            e = .multiply(e, try parsePower())
        }
        return e
    }

    // MARK: 求导、极限、积分、求和

    /// \frac{d}{dx}(…)、\frac{d^2}{dx^2}(…)、\frac{dy}{dx}、\frac{df}{dx}：当场求导。认不出这个样子就退回去当普通分式。
    private mutating func parseDerivativeOperator() throws -> MathExpr? {
        let start = i
        func fail() -> MathExpr? {
            i = start
            return nil
        }
        guard peek == .open("{"), token(at: i + 1) == .symbol("d") else { return nil }
        i += 2
        var order = 1
        if peek == .op("^"), case .number(let n)? = token(at: i + 1) {
            order = Int(n) ?? 1
            i += 2
        }
        var target: String?
        if case .symbol(let s)? = peek, s != "d" {
            target = s
            i += 1
        }
        guard case .close? = peek else { return fail() }
        i += 1
        guard peek == .open("{"), token(at: i + 1) == .symbol("d"), case .symbol(let v)? = token(at: i + 2) else { return fail() }
        i += 3
        if peek == .op("^") {
            i += 1
            _ = try parseScript()
        }
        guard case .close? = peek else { return fail() }
        i += 1
        var body: MathExpr
        if let t = target {
            guard let def = defined[t] else { throw unexpected("d\(t)/d\(v)（上面还没有写 \(t) = …）") }
            references.insert(t)
            body = def.body.substituting(def.variable, with: .symbol(v))
        } else {
            body = try parseFunctionArgument()
        }
        for _ in 0..<max(order, 1) { body = body.derivative(v) }
        usesDerivative = true
        return body
    }

    /// tokens[k...] 是不是正好「f(v)」（f 是已经写过的函数）。
    private func bareCall(at k: Int, variable v: String) -> String? {
        guard k + 3 < tokens.count, case .symbol(let name) = tokens[k], defined[name] != nil,
              tokens[k + 1] == .open("("), tokens[k + 2] == .symbol(v), case .close = tokens[k + 3] else { return nil }
        return name
    }

    /// \lim_{x\to a} …、\lim_{x\to 0^+} …、\lim_{x\to\infty} …
    private mutating func parseLimit() throws -> MathExpr {
        guard peek == .op("_"), token(at: i + 1) == .open("{") else { throw unexpected("\\lim 下面要写 x→…") }
        var depth = 0, j = i + 2
        while j < tokens.count {
            if case .open = tokens[j] { depth += 1 }
            if case .close = tokens[j] {
                if depth == 0 { break }
                depth -= 1
            }
            j += 1
        }
        guard j < tokens.count else { throw unexpected("\\lim 下面缺少 }") }
        let inner = Array(tokens[(i + 2)..<j])
        i = j + 1
        guard inner.count >= 3, case .symbol(let v) = inner[0], inner[1] == .arrow else {
            throw unexpected("\\lim 下面要写成 x→a")
        }
        var point = Array(inner[2...])
        var side = 0
        func sideOf(_ t: Token) -> Int? { t == .op("+") ? 1 : t == .op("-") ? -1 : nil }
        // 末尾的 ^{+}、^+、^{-}、^-，或者直接 0+、0-
        if point.count >= 4, point[point.count - 4] == .op("^"), point[point.count - 3] == .open("{"),
           let s = sideOf(point[point.count - 2]), case .close = point[point.count - 1] {
            side = s
            point.removeLast(4)
        } else if point.count >= 2, point[point.count - 2] == .op("^"), let s = sideOf(point[point.count - 1]) {
            side = s
            point.removeLast(2)
        } else if point.count >= 2, let s = sideOf(point[point.count - 1]) {
            side = s
            point.removeLast(1)
        }
        var sub = LatexExpression(point, functions: defined)
        let at = try sub.parseAll()
        references.formUnion(sub.references)
        if target == nil, bareCall(at: i, variable: v) != nil, token(at: i + 4) == nil || token(at: i + 4) == .equals {
            target = Target(name: bareCall(at: i, variable: v)!, kind: .limit)
        }
        let body = try parseOperand(boundTo: v)
        return .limit(v, at, side, body)
    }

    /// \lim、\sum 后面的式子：到下一个加减号为止（和乘除同级）；但后面的项里还有这个变量时一起算进来——
    /// 手写时括号常常省掉：\lim_{x\to\infty} \sqrt{x^2+x} - x。
    private mutating func parseOperand(boundTo v: String) throws -> MathExpr {
        var body = try parseProduct()
        while let t = peek, t == .op("+") || t == .op("-") {
            let saved = (i, tokens, references, target, usesDerivative)
            i += 1
            guard let term = try? parseProduct(), term.symbols.contains(v) else {
                (i, tokens, references, target, usesDerivative) = saved
                break
            }
            body = t == .op("+") ? .add(body, term) : .subtract(body, term)
        }
        return body
    }

    /// \int f dx（不定积分）、\int_a^b f dx（定积分，上下限可以是 ±∞）。
    private mutating func parseIntegral() throws -> MathExpr {
        var lower: MathExpr?, upper: MathExpr?
        while peek == .op("_") || peek == .op("^") {
            let isLower = peek == .op("_")
            i += 1
            let e = try parseBound()
            if isLower { lower = e } else { upper = e }
        }
        guard (lower == nil) == (upper == nil) else { throw unexpected("积分的上下限要写全") }
        let start = i
        differentialDepth += 1
        let body = try parseSum()
        differentialDepth -= 1
        let v: String
        if peek == .symbol("d"), case .symbol(let s)? = token(at: i + 1) {
            v = s
            i += 2
        } else {
            let free = body.symbols
            v = free.contains("x") || free.count != 1 ? "x" : free.first!
        }
        if target == nil, lower != nil, let name = bareCall(at: start, variable: v), token(at: start + 4) == .symbol("d") {
            target = Target(name: name, kind: .integral)
        }
        return .integral(v, lower, upper, body)
    }

    /// \sum_{k=1}^{n} …、\sum_{n=1}^{\infty} …、\prod_{k=1}^{n} …
    private mutating func parseSeries(product: Bool) throws -> MathExpr {
        var v: String?, lower: MathExpr?, upper: MathExpr?
        while peek == .op("_") || peek == .op("^") {
            let isLower = peek == .op("_")
            i += 1
            if isLower, peek == .open("{"), case .symbol(let s)? = token(at: i + 1), token(at: i + 2) == .equals {
                v = s
                i += 3
                lower = try parseSum()
                guard case .close? = peek else { throw unexpected(peek?.text ?? "缺少 }") }
                i += 1
            } else if isLower {
                lower = try parseBound()
            } else {
                upper = try parseBound()
            }
        }
        guard let lower, let upper else { throw unexpected(product ? "连乘要写上下界" : "求和要写上下界") }
        let start = i
        let body: MathExpr
        if let v { body = try parseOperand(boundTo: v) } else { body = try parseProduct() }
        let variable = v ?? (["n", "k", "i", "j", "m"].first { body.symbols.contains($0) } ?? "n")
        if target == nil, let name = bareCall(at: start, variable: variable) {
            target = Target(name: name, kind: .series)
        }
        return .series(variable, lower, upper, body, product)
    }
}
