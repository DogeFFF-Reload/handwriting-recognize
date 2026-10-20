import Foundation

/// 一行 LaTeX 的轻量解析：只为门禁回答「能不能解析、写了几项」，以及给说明模板取项。
/// 判对错仍归 MathEngine（P4），这里不做化简。
public struct WrittenTerm: Equatable {
    /// 学生写的原文（含符号），如 "-3x"。
    public var latex: String
    public var coef: Double
    public var pow: Int
}

public struct ParsedLine: Equatable {
    public enum Kind: String, Equatable { case function, derivative, other }
    public var kind: Kind
    /// 左边，如 "f(x)"、"f'(x)"；没有等号时为空。
    public var lhs: String
    /// 右边按书写顺序拆成的项；有项解析不了时为 nil。
    public var terms: [WrittenTerm]?
    public var rhs: String

    public var parseable: Bool { terms != nil && !(terms?.isEmpty ?? true) }
    public var termCount: Int { terms?.count ?? LatexTerms.split(rhs).count }
}

public enum LatexTerms {
    /// 统一写法：去空格、去 $、\left \right、统一撇号和减号、^{2} → ^2、\cdot/\times → *。
    public static func normalize(_ s: String) -> String {
        var t = s
        let pairs: [(String, String)] = [
            ("$", ""), ("\\left", ""), ("\\right", ""), ("\\,", ""), ("\\;", ""), ("\\!", ""), ("\\ ", ""),
            ("−", "-"), ("–", "-"), ("’", "'"), ("′", "'"), ("^{\\prime}", "'"), ("^\\prime", "'"), ("\\prime", "'"),
            ("\\cdot", "*"), ("\\times", "*"), ("·", "*"), ("×", "*"), ("²", "^2"), ("³", "^3"), ("⁴", "^4"),
        ]
        for (a, b) in pairs { t = t.replacingOccurrences(of: a, with: b) }
        t = t.filter { !$0.isWhitespace }
        // ^{12} → ^12（只处理纯数字）
        while let r = t.range(of: #"\^\{(-?\d+)\}"#, options: .regularExpression) {
            let inner = t[r].dropFirst(2).dropLast()
            t.replaceSubrange(r, with: "^" + inner)
        }
        return t
    }

    public static func parse(_ latex: String) -> ParsedLine {
        let s = normalize(latex)
        let parts = s.split(separator: "=", omittingEmptySubsequences: false).map(String.init)
        var lhs = "", rhs = s
        if parts.count == 2 { lhs = parts[0]; rhs = parts[1] }
        let kind: ParsedLine.Kind
        if lhs.range(of: #"^([a-z]'\(x\)|y')$"#, options: .regularExpression) != nil {
            kind = .derivative
        } else if lhs.range(of: #"^([a-z]\(x\)|y)$"#, options: .regularExpression) != nil {
            kind = .function
        } else {
            kind = .other
        }
        if parts.count > 2 { return ParsedLine(kind: .other, lhs: "", terms: nil, rhs: s) }
        let pieces = split(rhs)
        var terms: [WrittenTerm] = []
        for p in pieces {
            guard let (c, k) = monomial(p) else { return ParsedLine(kind: kind, lhs: lhs, terms: nil, rhs: rhs) }
            terms.append(WrittenTerm(latex: p, coef: c, pow: k))
        }
        return ParsedLine(kind: kind, lhs: lhs, terms: terms, rhs: rhs)
    }

    /// 在括号外的 + / - 处拆项，符号跟着后面的项。
    public static func split(_ rhs: String) -> [String] {
        var out: [String] = [], cur = "", depth = 0
        var prev: Character?
        for ch in rhs {
            if ch == "(" || ch == "{" { depth += 1 }
            if ch == ")" || ch == "}" { depth -= 1 }
            if (ch == "+" || ch == "-"), depth == 0, !cur.isEmpty, let p = prev, !"^*/({".contains(p) {
                out.append(cur)
                cur = String(ch)
            } else {
                cur.append(ch)
            }
            prev = ch
        }
        if !cur.isEmpty { out.append(cur) }
        return out.filter { $0 != "+" && $0 != "-" }
    }

    /// 单项式 → (系数, 次数)。支持 3、-3x、+x^2、\frac{1}{2}x^2、2*3x^2、0.5x。
    public static func monomial(_ term: String) -> (Double, Int)? {
        var t = term
        var sign = 1.0
        if t.hasPrefix("+") { t.removeFirst() } else if t.hasPrefix("-") { sign = -1; t.removeFirst() }
        guard !t.isEmpty else { return nil }
        var coef = 1.0, pow = 0
        // \frac{a}{b}
        while let r = t.range(of: #"\\[dt]?frac\{(-?[\d.]+)\}\{(-?[\d.]+)\}"#, options: .regularExpression) {
            let nums = t[r].components(separatedBy: CharacterSet(charactersIn: "{}")).compactMap { Double($0) }
            guard nums.count == 2, nums[1] != 0 else { return nil }
            coef *= nums[0] / nums[1]
            t.replaceSubrange(r, with: "")
        }
        var i = t.startIndex
        var sawSomething = coef != 1.0
        while i < t.endIndex {
            let ch = t[i]
            if ch.isNumber || ch == "." {
                var j = i
                while j < t.endIndex, t[j].isNumber || t[j] == "." { j = t.index(after: j) }
                guard let v = Double(t[i..<j]) else { return nil }
                coef *= v
                i = j
                sawSomething = true
            } else if ch == "x" {
                var j = t.index(after: i)
                var e = 1
                if j < t.endIndex, t[j] == "^" {
                    j = t.index(after: j)
                    var k = j
                    while k < t.endIndex, t[k].isNumber { k = t.index(after: k) }
                    guard k > j, let v = Int(t[j..<k]) else { return nil }
                    e = v
                    j = k
                }
                pow += e
                i = j
                sawSomething = true
            } else if ch == "*" {
                i = t.index(after: i)
            } else {
                return nil
            }
        }
        return sawSomething ? (sign * coef, pow) : nil
    }
}
