import Foundation

// 手写函数解析式（MyScript / Qwen 给的 LaTeX）→ 能求值的表达式，给函数图像用。
//
// 只认作图要用的那一小块 LaTeX：数字、x、π、e、+ − × ÷、^、\frac、\sqrt、括号、|x|、
// \sin \cos \tan \ln \log \exp 等，以及隐式乘法（3x、2\sin x、(x+1)(x-1)）。
// x 以外的单个字母（a、b、k…）当作参数，图像上给它们滑条（GeoGebra 的做法）；e 是自然常数。
// 判对错仍归 MathEngine（P4），这里只管「画得出来」。

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
    /// sin、cos、ln、sqrt、abs……；带底的对数是 call("log", [底, 真数])，n 次根是 call("root", [n, 被开方数])。
    case call(String, [MathExpr])

    /// 自然常数 e（Windows 上没有 M_E）。
    public static let euler = 2.718281828459045

    /// 求值。`values` 里放自变量和参数；没给值的参数按 1 算。
    public func evaluate(_ values: [String: Double]) -> Double {
        switch self {
        case .number(let v): return v
        case .symbol(let s):
            if let v = values[s] { return v }
            return s == "e" ? MathExpr.euler : 1
        case .negate(let a): return -a.evaluate(values)
        case .add(let a, let b): return a.evaluate(values) + b.evaluate(values)
        case .subtract(let a, let b): return a.evaluate(values) - b.evaluate(values)
        case .multiply(let a, let b): return a.evaluate(values) * b.evaluate(values)
        case .divide(let a, let b): return a.evaluate(values) / b.evaluate(values)
        case .power(let a, let b): return MathExpr.realPower(a.evaluate(values), b.evaluate(values))
        case .call(let name, let args):
            let v = args.map { $0.evaluate(values) }
            return MathExpr.apply(name, v)
        }
    }

    /// 出现过的符号（不含 e）。
    public var symbols: Set<String> {
        switch self {
        case .number: return []
        case .symbol(let s): return s == "e" ? [] : [s]
        case .negate(let a): return a.symbols
        case .add(let a, let b), .subtract(let a, let b), .multiply(let a, let b), .divide(let a, let b), .power(let a, let b):
            return a.symbols.union(b.symbols)
        case .call(_, let args): return args.reduce(into: Set<String>()) { $0.formUnion($1.symbols) }
        }
    }

    /// 只含数字系数时展开成多项式（次数 → 系数）；不是多项式、或带参数时返回 nil。
    public func polynomial(in variable: String) -> [Int: Double]? {
        func clean(_ p: [Int: Double]) -> [Int: Double] { p.filter { abs($0.value) > 1e-12 } }
        switch self {
        case .number(let v): return clean([0: v])
        case .symbol(let s):
            if s == variable { return [1: 1] }
            return s == "e" ? [0: MathExpr.euler] : nil
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
        case .call: return nil
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

    public static func parse(_ latex: String) throws -> FunctionDefinition {
        let tokens = try LatexExpression.tokenize(firstLine(latex))
        guard !tokens.isEmpty else { throw ParseError.empty }
        // 按顶层的第一个等号分左右
        var depth = 0
        var eq: Int?
        for (i, t) in tokens.enumerated() {
            switch t {
            case .open: depth += 1
            case .close: depth -= 1
            case .equals where depth == 0 && eq == nil: eq = i
            default: break
            }
        }
        guard let eq else {
            var p = LatexExpression(tokens)
            let body = try p.parseAll()
            let v = body.symbols.contains("x") || !body.symbols.contains("t") ? "x" : "t"
            return FunctionDefinition(name: "f", variable: v, body: body)
        }
        let lhs = Array(tokens[..<eq])
        var rhs = Array(tokens[(eq + 1)...])
        if let second = rhs.firstIndex(of: .equals) { rhs = Array(rhs[..<second]) }   // f(x) = … = …：只要第一段
        guard !rhs.isEmpty else { throw ParseError.empty }
        func letter(_ t: LatexExpression.Token) -> String? {
            if case .symbol(let s) = t { return s }
            return nil
        }
        let header: (name: String, variable: String)
        if lhs.count == 1, let n = letter(lhs[0]), n != "x" {
            header = (n, "x")                                    // y = …
        } else if lhs.count == 4, let n = letter(lhs[0]), lhs[1] == .open("("), let v = letter(lhs[2]), case .close = lhs[3] {
            header = (n, v)                                      // f(x) = …
        } else {
            throw ParseError.notAFunction(lhs.map(\.text).joined())
        }
        var p = LatexExpression(rhs)
        return FunctionDefinition(name: header.name, variable: header.variable, body: try p.parseAll())
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

/// 递归下降解析。优先级：加减 < 乘除（含隐式乘法）< 正负号 < 乘方（右结合）。
struct LatexExpression {
    enum Token: Equatable {
        case number(String)
        case symbol(String)
        case command(String)        // 不带反斜杠：sin、frac、sqrt、pi……
        case op(Character)          // + - * / ^ _
        case open(Character)        // ( { [
        case close(Character)       // ) } ]
        case bar                    // |
        case equals

        var text: String {
            switch self {
            case .number(let s), .symbol(let s): return s
            case .command(let s): return "\\" + s
            case .op(let c), .open(let c), .close(let c): return String(c)
            case .bar: return "|"
            case .equals: return "="
            }
        }
    }

    static let functions: Set<String> = ["sin", "cos", "tan", "cot", "sec", "csc", "arcsin", "arccos", "arctan",
                                         "sinh", "cosh", "tanh", "ln", "lg", "log", "exp"]

    var tokens: [Token]
    var i = 0
    var absDepth = 0

    init(_ tokens: [Token]) { self.tokens = tokens }

    // MARK: 词法

    static func tokenize(_ latex: String) throws -> [Token] {
        var s = latex
        let pairs: [(String, String)] = [
            ("$", ""), ("\\displaystyle", ""), ("\\left", ""), ("\\right", ""), ("\\bigl", ""), ("\\bigr", ""),
            ("\\Big", ""), ("\\big", ""), ("\\,", ""), ("\\;", ""), ("\\:", ""), ("\\!", ""), ("\\ ", ""), ("~", ""),
            ("\\dfrac", "\\frac"), ("\\tfrac", "\\frac"), ("\\cdot", "*"), ("\\times", "*"), ("\\ast", "*"), ("\\div", "/"),
            ("\\lvert", "|"), ("\\rvert", "|"), ("\\vert", "|"), ("\\mid", "|"), ("\\{", "("), ("\\}", ")"),
            ("\\lbrace", "("), ("\\rbrace", ")"), ("\\lbrack", "("), ("\\rbrack", ")"),
            ("−", "-"), ("–", "-"), ("×", "*"), ("·", "*"), ("⋅", "*"), ("÷", "/"), ("π", "\\pi "),
            ("²", "^2"), ("³", "^3"), ("√", "\\sqrt "), ("’", "'"), ("′", "'"),
        ]
        for (a, b) in pairs { s = s.replacingOccurrences(of: a, with: b) }

        var out: [Token] = []
        let chars = Array(s)
        var k = 0
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
                // \operatorname{sin}、\mathrm{e}、\text{…}：取花括号里的字，当成函数名或字母
                if ["operatorname", "mathrm", "mathit", "text", "textrm", "mathbf"].contains(name) {
                    guard k < chars.count, chars[k] == "{", let end = chars[k...].firstIndex(of: "}") else {
                        throw FunctionDefinition.ParseError.unexpected("\\" + name)
                    }
                    let word = String(chars[(k + 1)..<end]).filter { !$0.isWhitespace }
                    k = end + 1
                    if word.count == 1 { out.append(.symbol(word)) }
                    else if functions.contains(word) { out.append(.command(word)) }
                    else if !word.isEmpty { throw FunctionDefinition.ParseError.unexpected(word) }
                    continue
                }
                out.append(.command(name))
                continue
            }
            if c.isLetter {
                // 识别器偶尔把 sin、ln 写成普通字母：连着的函数名照样认
                if let f = functions.sorted(by: { $0.count > $1.count }).first(where: { name in
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

    private mutating func next() -> Token? {
        defer { i += 1 }
        return peek
    }

    private mutating func expect(_ t: Token) throws {
        guard peek == t else { throw FunctionDefinition.ParseError.unexpected(peek?.text ?? "结尾") }
        i += 1
    }

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
            else if startsFactor(t) { e = .multiply(e, try parsePower()) }   // 3x、2\sin x、(x+1)(x-1)
            else { break }
        }
        return e
    }

    private mutating func parseSigned() throws -> MathExpr {
        if peek == .op("-") { i += 1; return .negate(try parseSigned()) }
        if peek == .op("+") { i += 1; return try parseSigned() }
        return try parsePower()
    }

    private mutating func parsePower() throws -> MathExpr {
        let base = try parsePrimary()
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

    /// ^ 或 _ 后面的部分：{…} 整组；不带括号时按 LaTeX 只取一个字符（x^23 是 x² · 3）。
    private mutating func parseScript() throws -> MathExpr {
        guard let t = peek else { throw FunctionDefinition.ParseError.unexpected("结尾") }
        switch t {
        case .open:
            return try parseGroup()
        case .number(let s):
            if s.count > 1, !s.contains(".") {
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
        guard case .open(let o) = next() else { throw FunctionDefinition.ParseError.unexpected(tokens[i - 1].text) }
        let saved = absDepth
        absDepth = 0
        let e = try parseSum()
        absDepth = saved
        // 手写识别偶尔给出 ( … } 这种配不上的括号：只要是右括号就收
        guard case .close = peek else {
            throw FunctionDefinition.ParseError.unexpected(peek?.text ?? "缺少与 \(o) 对应的右括号")
        }
        i += 1
        return e
    }

    private func startsFactor(_ t: Token) -> Bool {
        switch t {
        case .number, .symbol, .open: return true
        case .command(let c): return c != "right"
        case .bar: return absDepth == 0
        default: return false
        }
    }

    private mutating func parsePrimary() throws -> MathExpr {
        guard let t = peek else { throw FunctionDefinition.ParseError.unexpected("结尾") }
        switch t {
        case .number(let s):
            i += 1
            guard let v = Double(s) else { throw FunctionDefinition.ParseError.unexpected(s) }
            return .number(v)
        case .symbol(let s):
            i += 1
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
            throw FunctionDefinition.ParseError.unexpected(t.text)
        }
    }

    private mutating func parseCommand(_ name: String) throws -> MathExpr {
        switch name {
        case "pi": return .number(Double.pi)
        case "frac":
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
            throw FunctionDefinition.ParseError.unexpected("\\" + name)
        }
    }

    /// \frac、\sqrt 的参数：{…} 整组，否则一个字符。
    private mutating func parseScriptOrGroup() throws -> MathExpr {
        if case .open = peek { return try parseGroup() }
        return try parseScript()
    }

    /// 函数的参数：(…) 整组；没括号时一直吃到加减号或下一个函数（\sin 2x → sin(2x)，\sin x\cos x → sin x · cos x）。
    private mutating func parseFunctionArgument() throws -> MathExpr {
        if case .open = peek {
            let g = try parseGroup()
            // \sin(x)^2 当作 (sin x)^2 的情形由外层的乘方处理；这里只收括号里的
            return g
        }
        var e = try parseSigned()
        while let t = peek, startsFactor(t) {
            if case .command(let c) = t, Self.functions.contains(c) { break }
            e = .multiply(e, try parsePower())
        }
        return e
    }
}
