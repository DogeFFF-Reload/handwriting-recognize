//
//  Core.swift
//  MathEngine
//
//  受限多项式引擎：LaTeX → 有理系数多项式 → 求导 / 比对 / 场景。
//  只覆盖演示需要的写法，超出范围一律抛 MathError.unsupported，绝不"假装化简成功"。
//
//  v3（2026-10-20）：已在 Swift 6.0.3 / Linux 上 `swift test` 全绿。
//  加固了溢出（任何输入都不会让 App 闪退）、数字位数、指数与次数上限。
//

import Foundation

// MARK: - 错误

public enum MathError: Error, Equatable, CustomStringConvertible {
    case emptyInput
    case badCharacter(String)
    case unexpectedToken(String)
    case unexpectedEnd
    case unsupported(String)

    public var description: String {
        switch self {
        case .emptyInput: return "空输入"
        case .badCharacter(let c): return "看不懂的字符 \(c)"
        case .unexpectedToken(let t): return "多余的记号 \(t)"
        case .unexpectedEnd: return "式子没写完"
        case .unsupported(let why): return "超出演示范围：\(why)"
        }
    }
}

// MARK: - 有理数

/// 有理数。演示里系数只有整数和二分之一，用 Rational 是为了让 `==` 精确相等，
/// 不要用 Double 判等 —— `0.1 + 0.2 != 0.3` 会让「判对错」在边界上抖。
///
/// v3 加固：**任何运算都不会让 App 崩溃**。Swift 的 Int 溢出默认直接 trap（真机上就是闪退），
/// 识别器吐出 `99999999999x^9` 这种垃圾时必须扛住。溢出、除零一律得到 `Rational.invalid`
/// （d == 0），它会沿着运算一路传下去，解析器在出口处统一检查并抛 `.unsupported`。
public struct Rational: Equatable, Comparable, CustomStringConvertible {
    public private(set) var n: Int
    public private(set) var d: Int

    /// 溢出 / 除零的哨兵。d == 0 只可能出现在这里。
    public static let invalid = Rational(raw: 0, 0)

    private init(raw n: Int, _ d: Int) {
        self.n = n
        self.d = d
    }

    public init(_ n: Int, _ d: Int = 1) {
        // 不用 precondition：分母为 0、Int.min 取反都会返回 invalid 而不是闪退
        guard d != 0, n != Int.min, d != Int.min else {
            self.n = 0
            self.d = 0
            return
        }
        var nn = n
        var dd = d
        if dd < 0 { nn = -nn; dd = -dd }
        let g = Rational.gcd(Swift.abs(nn), dd)
        if g > 1 { nn /= g; dd /= g }
        self.n = nn
        self.d = dd
    }

    public static let zero = Rational(0)
    public static let one = Rational(1)

    public var isValid: Bool { d != 0 }
    public var isZero: Bool { n == 0 && d != 0 }
    public var isNegative: Bool { n < 0 }
    public var doubleValue: Double { d == 0 ? .nan : Double(n) / Double(d) }
    public var description: String {
        if d == 0 { return "NaN" }
        return d == 1 ? "\(n)" : "\(n)/\(d)"
    }

    public static func gcd(_ a: Int, _ b: Int) -> Int {
        var x = a
        var y = b
        while y != 0 { let t = x % y; x = y; y = t }
        return x == 0 ? 1 : x
    }

    /// 三个乘加都带溢出检查，任何一步溢出 → invalid
    private static func combine(_ a: Int, _ b: Int, _ c: Int, _ e: Int, _ den1: Int, _ den2: Int,
                                subtract: Bool) -> Rational {
        let (x, o1) = a.multipliedReportingOverflow(by: b)
        let (y, o2) = c.multipliedReportingOverflow(by: e)
        let (s, o3) = subtract ? x.subtractingReportingOverflow(y) : x.addingReportingOverflow(y)
        let (dd, o4) = den1.multipliedReportingOverflow(by: den2)
        if o1 || o2 || o3 || o4 { return .invalid }
        return Rational(s, dd)
    }

    public static func + (l: Rational, r: Rational) -> Rational {
        guard l.isValid, r.isValid else { return .invalid }
        return combine(l.n, r.d, r.n, l.d, l.d, r.d, subtract: false)
    }
    public static func - (l: Rational, r: Rational) -> Rational {
        guard l.isValid, r.isValid else { return .invalid }
        return combine(l.n, r.d, r.n, l.d, l.d, r.d, subtract: true)
    }
    public static func * (l: Rational, r: Rational) -> Rational {
        guard l.isValid, r.isValid else { return .invalid }
        let (nn, o1) = l.n.multipliedReportingOverflow(by: r.n)
        let (dd, o2) = l.d.multipliedReportingOverflow(by: r.d)
        if o1 || o2 { return .invalid }
        return Rational(nn, dd)
    }
    public static func / (l: Rational, r: Rational) -> Rational {
        guard l.isValid, r.isValid, !r.isZero else { return .invalid }
        let (nn, o1) = l.n.multipliedReportingOverflow(by: r.d)
        let (dd, o2) = l.d.multipliedReportingOverflow(by: r.n)
        if o1 || o2 { return .invalid }
        return Rational(nn, dd)
    }
    public static prefix func - (v: Rational) -> Rational {
        guard v.isValid else { return .invalid }
        return Rational(-v.n, v.d)
    }

    public static func < (l: Rational, r: Rational) -> Bool {
        let (a, o1) = l.n.multipliedReportingOverflow(by: r.d)
        let (b, o2) = r.n.multipliedReportingOverflow(by: l.d)
        if o1 || o2 || !l.isValid || !r.isValid { return l.doubleValue < r.doubleValue }
        return a < b
    }

    public var abs: Rational { n < 0 ? -self : self }

    /// 从 JSON 里的 Double 还原（0.5、3.0 这类有限小数能精确还原）。
    /// 非有限值、绝对值 ≥ 1e9 一律 invalid（滑条和识别器都不会合法地产生这种数）。
    public static func fromDouble(_ v: Double) -> Rational {
        guard v.isFinite, Swift.abs(v) < 1e9 else { return .invalid }
        if v == v.rounded() { return Rational(Int(v)) }
        return Rational(Int((v * 1_000_000).rounded()), 1_000_000)
    }

    /// 在有理数点上精确求值时用
    public func power(_ e: Int) -> Rational {
        var acc = Rational.one
        var k = 0
        while k < e { acc = acc * self; k += 1 }
        return acc
    }
}

/// 解析上限：超过就当"超出演示范围"，而不是硬算到溢出
public enum Limits {
    /// 数字最多几位（整数部分 + 小数部分，不含小数点）
    public static let maxDigits = 9
    /// 指数上限：演示最多四次，留余量
    public static let maxExponent = 12
    /// 多项式次数上限（防止 (x+1)^12 * (x+1)^12 这种）
    public static let maxDegree = 24
}

// MARK: - 单项与多项式

public struct Term: Equatable {
    public var coef: Rational
    public var pow: Int
    public init(_ coef: Rational, _ pow: Int) {
        self.coef = coef
        self.pow = pow
    }
    /// 降幂排序用
    public var degree: Int { pow }
}

/// 单变量多项式，按幂次降序、同幂合并、去掉零系数。
public struct Poly: Equatable {
    public private(set) var terms: [Term]

    public init(_ terms: [Term]) {
        var byPow: [Int: Rational] = [:]
        for t in terms where !t.coef.isZero {
            byPow[t.pow, default: .zero] = byPow[t.pow, default: .zero] + t.coef
        }
        self.terms = byPow
            .filter { !$0.value.isZero }
            .map { Term($0.value, $0.key) }
            .sorted { $0.pow > $1.pow }
    }

    public init(_ coef: Rational, _ pow: Int) { self.init([Term(coef, pow)]) }
    public static let zero = Poly([])
    public static func constant(_ v: Rational) -> Poly { Poly([Term(v, 0)]) }

    public var isZero: Bool { terms.isEmpty }
    public var degree: Int { terms.first?.pow ?? -1 }
    public var isConstant: Bool { terms.allSatisfy { $0.pow == 0 } }
    /// 有任何一个系数溢出过就是 false。解析器出口统一检查它。
    public var isValid: Bool { terms.allSatisfy { $0.coef.isValid } }

    /// 在有理数点上精确求值（定积分的牛顿-莱布尼茨用）
    public func evaluate(_ x: Rational) -> Rational {
        var acc = Rational.zero
        for t in terms { acc = acc + t.coef * x.power(t.pow) }
        return acc
    }

    /// 原函数（不带 +C）
    public func antiderivative() -> Poly {
        Poly(terms.map { Term($0.coef / Rational($0.pow + 1), $0.pow + 1) })
    }

    public func coef(of pow: Int) -> Rational {
        for t in terms where t.pow == pow { return t.coef }
        return .zero
    }

    public func callAsFunction(_ x: Double) -> Double {
        var acc = 0.0
        for t in terms {
            var v = 1.0
            var k = 0
            while k < t.pow { v *= x; k += 1 }
            acc += t.coef.doubleValue * v
        }
        return acc
    }

    public static func + (l: Poly, r: Poly) -> Poly { Poly(l.terms + r.terms) }
    public static func - (l: Poly, r: Poly) -> Poly { Poly(l.terms + r.terms.map { Term(-$0.coef, $0.pow) }) }
    public static prefix func - (v: Poly) -> Poly { Poly(v.terms.map { Term(-$0.coef, $0.pow) }) }

    public static func * (l: Poly, r: Poly) -> Poly {
        if l.isZero || r.isZero { return .zero }
        var out: [Term] = []
        for a in l.terms {
            for b in r.terms {
                out.append(Term(a.coef * b.coef, a.pow + b.pow))
            }
        }
        return Poly(out)
    }

    public func raised(to e: Int) -> Poly {
        guard e > 0 else { return Poly.constant(.one) }
        var acc = Poly.constant(.one)
        for _ in 0..<e { acc = acc * self }
        return acc
    }

    /// 只支持除以常数（`\frac{x^2}{2}` 这种）
    public func divided(by other: Poly) throws -> Poly {
        guard other.isConstant, let c = other.terms.first else {
            if other.isZero { throw MathError.unsupported("除数是 0") }
            throw MathError.unsupported("只能除以常数，不支持除以含 x 的式子")
        }
        return Poly(terms.map { Term($0.coef / c.coef, $0.pow) })
    }

    public func derivative() -> Poly {
        Poly(terms.filter { $0.pow > 0 }.map { Term($0.coef * Rational($0.pow), $0.pow - 1) })
    }

    public func secondDerivative() -> Poly { derivative().derivative() }

    /// 展开成可比较的字符串，调试用
    public var canonical: String {
        if terms.isEmpty { return "0" }
        var parts: [String] = []
        for t in terms {
            let coefPart = t.coef.description
            if t.pow == 0 { parts.append(coefPart); continue }
            let body = t.pow == 1 ? "x" : "x^\(t.pow)"
            parts.append("\(coefPart)*\(body)")
        }
        return parts.joined(separator: " + ")
    }
}

// MARK: - LaTeX 清洗（只做演示用得上的那些）

public enum LatexText {

    static let superscripts: [Character: Character] = [
        "⁰": "0", "¹": "1", "²": "2", "³": "3", "⁴": "4",
        "⁵": "5", "⁶": "6", "⁷": "7", "⁸": "8", "⁹": "9",
        "⁺": "+", "⁻": "-",
    ]

    /// Unicdoe 上标 → ^(...)；全角/减号/乘号统一
    public static func fixUnicode(_ s: String) -> String {
        var out = ""
        var buffer: [Character] = []

        func flush() {
            guard !buffer.isEmpty else { return }
            let body = String(buffer.map { superscripts[$0] ?? $0 })
            out += "^(" + body + ")"
            buffer.removeAll()
        }

        for ch in s {
            if superscripts[ch] != nil {
                buffer.append(ch)
            } else {
                flush()
                switch ch {
                case "−", "–", "—", "‐": out.append("-")
                case "×", "·", "⋅": out.append("*")
                case "÷": out.append("/")
                case "＝": out.append("=")
                case "（": out.append("(")
                case "）": out.append(")")
                case "，": out.append(",")
                case "′": out.append("'")
                case "″": out.append("''")
                case "\u{2009}", "\u{200A}", "\u{00A0}": out.append(" ")
                default: out.append(ch)
                }
            }
        }
        flush()
        return out
    }

    /// 去掉 \left \right \, \; \! \quad 之类，统一 \cdot \times \div \prime
    public static func stripMacros(_ s: String) -> String {
        var t = s
        // \mathrm{f}(x) / \mathit{f}(x) 这类包一层字体命令的写法要先剥掉，
        // 否则标签认不出来（iink 导出很可能会这么写）
        t = stripWrappers(t)
        let junk = ["\\left", "\\right", "\\!", "\\;", "\\,", "\\:", "\\ ", "\\quad", "\\qquad"]
        for j in junk { t = t.replacingOccurrences(of: j, with: " ") }
        t = t.replacingOccurrences(of: "\\cdot", with: "*")
        t = t.replacingOccurrences(of: "\\times", with: "*")
        t = t.replacingOccurrences(of: "\\div", with: "/")
        t = t.replacingOccurrences(of: "\\prime", with: "'")
        return t
    }

    /// \mathrm{...} / \mathit{...} / \text{...} 等：只留花括号里的内容，递归
    public static func stripWrappers(_ s: String) -> String {
        let names = ["\\mathrm", "\\mathit", "\\mathbf", "\\mathsf", "\\textrm", "\\text", "\\operatorname"]
        let chars = Array(s)
        var out: [Character] = []
        var i = 0
        while i < chars.count {
            var matched = false
            if chars[i] == "\\" {
                for name in names {
                    let n = Array(name)
                    let end = i + n.count
                    if end < chars.count, Array(chars[i..<end]) == n, chars[end] == "{" {
                        if let close = matchBrace(chars, end) {
                            let inner = String(chars[(end + 1)..<close])
                            out.append(contentsOf: Array(stripWrappers(inner)))
                            i = close + 1
                            matched = true
                            break
                        }
                    }
                }
            }
            if !matched {
                out.append(chars[i])
                i += 1
            }
        }
        return String(out)
    }

    /// \frac{a}{b} → (a)/(b)，递归处理嵌套
    public static func expandFrac(_ s: String) -> String {
        let chars = Array(s)
        var out = ""
        var i = 0
        while i < chars.count {
            if i + 4 < chars.count, chars[i] == "\\",
               chars[i + 1] == "f", chars[i + 2] == "r", chars[i + 3] == "a", chars[i + 4] == "c" {
                let afterFrac = i + 5
                if afterFrac < chars.count, chars[afterFrac] == "{" {
                    if let aEnd = matchBrace(chars, afterFrac) {
                        let aBody = String(chars[(afterFrac + 1)..<aEnd])
                        let bStart = aEnd + 1
                        if bStart < chars.count, chars[bStart] == "{", let bEnd = matchBrace(chars, bStart) {
                            let bBody = String(chars[(bStart + 1)..<bEnd])
                            out += "((" + expandFrac(aBody) + ")/(" + expandFrac(bBody) + "))"
                            i = bEnd + 1
                            continue
                        }
                    }
                }
                out.append(chars[i])
                i += 1
                continue
            }
            out.append(chars[i])
            i += 1
        }
        return out
    }

    static func matchBrace(_ chars: [Character], _ start: Int) -> Int? {
        var depth = 0
        var i = start
        while i < chars.count {
            if chars[i] == "{" { depth += 1 }
            if chars[i] == "}" {
                depth -= 1
                if depth == 0 { return i }
            }
            i += 1
        }
        return nil
    }

    /// `3x^{2}` → `3x^2`。契约样例里不带花括号，SwiftMath 两种都能排；
    /// 只在对外输出（Annotation 的 expected_latex）时用，内部仍走 normalizeCaret。
    public static func compactExponents(_ s: String) -> String {
        var out = s
        while let r = out.range(of: #"\^\{[0-9]+\}"#, options: .regularExpression) {
            let inner = out[r].dropFirst(2).dropLast()
            out.replaceSubrange(r, with: "^" + inner)
        }
        return out
    }

    /// 括号统一、^ 展开
    public static func normalizeCaret(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "{", with: "(").replacingOccurrences(of: "}", with: ")")
        t = t.replacingOccurrences(of: "**", with: "^")
        return t
    }
}

// MARK: - 标签剥离

public enum LineShape {
    case expression(String)
    case equation(lhs: String, rhs: String)
    case labelled(label: String, body: String)

    /// `f'(x)=…` / `f(x)=…` / `y=…` → labelled；`2x+3=7` → equation
    public static func split(_ latex: String) -> LineShape {
        let cleaned = LatexText.normalizeCaret(
            LatexText.expandFrac(LatexText.stripMacros(LatexText.fixUnicode(latex)))
        )
        let chars = Array(cleaned)
        var depth = 0
        var eqIndex: Int? = nil
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "(" { depth += 1 }
            if c == ")" { depth -= 1 }
            if c == "=" && depth == 0 && eqIndex == nil { eqIndex = i }
            i += 1
        }
        guard let eq = eqIndex else { return .expression(cleaned) }
        let lhs = String(chars[0..<eq]).trimmingCharacters(in: .whitespaces)
        let rhs = String(chars[(eq + 1)..<chars.count]).trimmingCharacters(in: .whitespaces)
        if isLabel(lhs) { return .labelled(label: lhs, body: rhs) }
        return .equation(lhs: lhs, rhs: rhs)
    }

    /// f(x) / f'(x) / f''(x) / f^{\\prime}(x) / y / g
    static func isLabel(_ lhs: String) -> Bool {
        // 1) 去掉空白、上下标括号、乘号、撇号
        var squeezed = lhs.filter { !" ^_{}*'′″".contains($0) }
        // 2) 花括号统一成圆括号后会留下空的 ()：f^(')(x) → f()(x) → f(x)
        while squeezed.contains("()") {
            squeezed = squeezed.replacingOccurrences(of: "()", with: "")
        }
        let chars = Array(squeezed)
        if chars.count == 4, chars[0].isLetter, chars[1] == "(", chars[3] == ")", chars[2].isLetter {
            return true
        }
        if chars.count == 1, let c = chars.first, "yfg".contains(c) {
            return true
        }
        return false
    }
}

// MARK: - 词法

enum Tok {
    case num(Rational)
    case x
    case plus, minus, star, slash, caret
    case lparen, rparen

    var isValue: Bool {
        switch self {
        case .num, .x, .rparen: return true
        default: return false
        }
    }
    var startsValue: Bool {
        switch self {
        case .num, .x, .lparen: return true
        default: return false
        }
    }
}

// MARK: - 解析器（递归下降，直接算成 Poly）

public struct PolyParser {

    public init() {}

    /// 一行正文 → 多项式。抛出 MathError。
    public static func parse(_ body: String) throws -> Poly {
        let toks = try tokenize(body)
        var index = 0
        let result = try parseExpr(toks, &index)
        if index < toks.count {
            throw MathError.unexpectedToken(describe(toks[index]))
        }
        guard result.isValid else {
            throw MathError.unsupported("数字太大，超出演示范围")
        }
        return result
    }

    static func describe(_ t: Tok) -> String {
        switch t {
        case .num(let r): return r.description
        case .x: return "x"
        case .plus: return "+"
        case .minus: return "-"
        case .star: return "*"
        case .slash: return "/"
        case .caret: return "^"
        case .lparen: return "("
        case .rparen: return ")"
        }
    }

    static func tokenize(_ body: String) throws -> [Tok] {
        var raw: [Tok] = []
        let chars = Array(body)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == " " || c == "\t" || c == "\n" {
                i += 1
                continue
            }
            if c.isNumber {
                var text = String(c)
                i += 1
                while i < chars.count, chars[i].isNumber || chars[i] == "." {
                    text.append(chars[i])
                    i += 1
                }
                // 识别器把一行字读成一长串数字时，不要硬算到溢出
                if text.filter({ $0 != "." }).count > Limits.maxDigits {
                    throw MathError.unsupported("数字太长：\(text.prefix(12))…")
                }
                // isNumber 对 "²"、"½"、"٣" 也成立，Double() 会返回 nil，这里当作看不懂的字符
                guard let d = Double(text) else { throw MathError.badCharacter(text) }
                let r = Rational.fromDouble(d)
                guard r.isValid else { throw MathError.unsupported("数字太大：\(text)") }
                raw.append(.num(r))
                continue
            }
            if c == "x" || c == "X" {
                raw.append(.x)
                i += 1
                continue
            }
            switch c {
            case "+": raw.append(.plus)
            case "-": raw.append(.minus)
            case "*": raw.append(.star)
            case "/": raw.append(.slash)
            case "^": raw.append(.caret)
            case "(": raw.append(.lparen)
            case ")": raw.append(.rparen)
            case "=": throw MathError.unsupported("解析前应先用 LineShape.split 去掉等号")
            default:
                throw MathError.badCharacter(String(c))
            }
            i += 1
        }
        // 补隐式乘号：2x、3(x+1)、(x+1)(x-1)、x(x+1)
        var toks: [Tok] = []
        var prev: Tok? = nil
        for t in raw {
            if let p = prev, p.isValue, t.startsValue {
                toks.append(.star)
            }
            toks.append(t)
            prev = t
        }
        if toks.isEmpty { throw MathError.emptyInput }
        return toks
    }

    static func parseExpr(_ toks: [Tok], _ i: inout Int) throws -> Poly {
        var acc = try parseTerm(toks, &i)
        while i < toks.count {
            if case .plus = toks[i] {
                i += 1
                acc = acc + (try parseTerm(toks, &i))
            } else if case .minus = toks[i] {
                i += 1
                acc = acc - (try parseTerm(toks, &i))
            } else {
                break
            }
        }
        return acc
    }

    static func parseTerm(_ toks: [Tok], _ i: inout Int) throws -> Poly {
        var acc = try parseUnary(toks, &i)
        while i < toks.count {
            if case .star = toks[i] {
                i += 1
                let rhs = try parseUnary(toks, &i)
                guard acc.degree + rhs.degree <= Limits.maxDegree else {
                    throw MathError.unsupported("次数太高")
                }
                acc = acc * rhs
            } else if case .slash = toks[i] {
                i += 1
                acc = try acc.divided(by: try parseUnary(toks, &i))
            } else {
                break
            }
        }
        return acc
    }

    static func parseUnary(_ toks: [Tok], _ i: inout Int) throws -> Poly {
        if i < toks.count, case .minus = toks[i] {
            i += 1
            return -(try parseUnary(toks, &i))
        }
        if i < toks.count, case .plus = toks[i] {
            i += 1
            return try parseUnary(toks, &i)
        }
        return try parsePower(toks, &i)
    }

    static func parsePower(_ toks: [Tok], _ i: inout Int) throws -> Poly {
        let base = try parseAtom(toks, &i)
        if i < toks.count, case .caret = toks[i] {
            i += 1
            let expPoly = try parseUnary(toks, &i)
            guard expPoly.isConstant else {
                throw MathError.unsupported("指数必须是正整数")
            }
            let e = expPoly.coef(of: 0)
            guard e.isValid, e.d == 1, e.n >= 0 else {
                throw MathError.unsupported("指数必须是正整数")
            }
            guard e.n <= Limits.maxExponent,
                  Swift.max(base.degree, 0) * e.n <= Limits.maxDegree else {
                throw MathError.unsupported("指数太大")
            }
            return base.raised(to: e.n)
        }
        return base
    }

    static func parseAtom(_ toks: [Tok], _ i: inout Int) throws -> Poly {
        guard i < toks.count else { throw MathError.unexpectedEnd }
        switch toks[i] {
        case .num(let r):
            i += 1
            return Poly.constant(r)
        case .x:
            i += 1
            return Poly(Rational(1), 1)
        case .lparen:
            i += 1
            let inner = try parseExpr(toks, &i)
            guard i < toks.count, case .rparen = toks[i] else { throw MathError.unexpectedEnd }
            i += 1
            return inner
        default:
            throw MathError.unexpectedToken(describe(toks[i]))
        }
    }
}

// MARK: - 带位置的项（画圈要用原文位置）

public struct SourceTerm: Equatable {
    public var coef: Rational
    public var pow: Int
    public var span: Range<Int>?     // 在 body 字符数组里的区间
    public var text: String?         // 学生原文（如 "-3x"）
}

public struct StudentLine {
    public var poly: Poly
    public var terms: [SourceTerm]
    public var body: String
    /// 等号左边的标签（`f'(x)` 之类），没有就是 nil。估算错项在整行里的横向位置时要算上它
    public var label: String? = nil

    /// 一行 LaTeX → 带位置的项。标签会被剥掉，区间是相对 body 的。
    /// 正文为空（`f'(x)=` 还没写）时抛 `.emptyInput`，不再当成 0 去比对。
    public static func parse(_ latex: String) throws -> StudentLine {
        let shape = LineShape.split(latex)
        let body: String
        var label: String? = nil
        switch shape {
        case .labelled(let l, let b): body = b; label = l
        case .expression(let s): body = s
        case .equation(_, _):
            throw MathError.unsupported("这一行是等式，请用残差形式处理")
        }
        let chars = Array(body)
        let chunks = chunkRanges(chars)
        var out: [SourceTerm] = []
        var poly = Poly.zero
        for (range, text) in chunks {
            let sub: Poly
            do {
                sub = try PolyParser.parse(text)
            } catch MathError.emptyInput {
                continue
            }
            poly = poly + sub
            if sub.terms.isEmpty {
                // 学生写了常数 0（例如 "f'(x)=0"）：Poly 会把零项合并掉，
                // 但这一项确实写在纸上，保留排版位置和原文，否则整行会被当成"什么都没写"
                let txt = text.trimmingCharacters(in: .whitespaces)
                if !txt.isEmpty {
                    out.append(SourceTerm(coef: .zero, pow: 0, span: range, text: txt))
                }
                continue
            }
            if sub.terms.count == 1, let only = sub.terms.first {
                out.append(SourceTerm(coef: only.coef, pow: only.pow,
                                      span: range, text: text.trimmingCharacters(in: .whitespaces)))
            } else {
                for t in sub.terms {
                    out.append(SourceTerm(coef: t.coef, pow: t.pow, span: nil, text: nil))
                }
            }
        }
        if out.isEmpty { throw MathError.emptyInput }
        guard poly.isValid else { throw MathError.unsupported("数字太大，超出演示范围") }
        return StudentLine(poly: poly, terms: out, body: body, label: label)
    }

    /// 契约里的 `char_span`（相对 `body`）对应学生写的第几项。找不到返回 nil。
    /// InkCore 的桥用它把错项对到 P3 的 `TermSegmenter` 框上。
    public func termIndex(forCharSpan span: Range<Int>) -> Int? {
        terms.firstIndex { $0.span == span }
    }

    /// 按顶层 +/- 切块，块里带着原字符区间
    static func chunkRanges(_ chars: [Character]) -> [(Range<Int>, String)] {
        var ranges: [Range<Int>] = []
        var depth = 0
        var start = 0
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "(" { depth += 1 }
            if c == ")" { depth -= 1 }
            if (c == "+" || c == "-") && depth == 0 && i > start {
                let prev = chars[i - 1]
                if "+-*/^(".contains(prev) {
                    i += 1
                    continue
                }
                ranges.append(start..<i)
                start = i
            }
            i += 1
        }
        ranges.append(start..<chars.count)
        var out: [(Range<Int>, String)] = []
        for r in ranges {
            let text = String(chars[r])
            if text.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            if text == "+" || text == "-" { continue }
            out.append((r, text))
        }
        return out
    }
}
