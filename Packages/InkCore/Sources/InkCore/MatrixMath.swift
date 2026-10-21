import Foundation
import MathEngine

/// 「矩阵」二级菜单里的四种运算。
public enum MatrixAction: String, CaseIterable, Equatable, Sendable {
    case calculate
    case inverse
    case determinant
    /// 2×2 矩阵：看它把单位方格变成什么样（卡片里拖基向量、做逆变换）。
    case transform
}

/// 矩阵运算。识别结果里出现 pmatrix / bmatrix / matrix / array 时，菜单多一枚「矩阵」。
/// 计算吃掉这一段里的一个或多个矩阵（加、减、乘、数乘、转置、已经写上的 ^{-1}）；
/// 求逆、求行列式先把式子算成一个矩阵，再往下做。元素只认常数。
/// 左边可以写名字：A = \begin{pmatrix}…\end{pmatrix}，结果写成「A = …，A^{-1} = …」。
public enum MatrixMath {
    public static func contains(_ latex: String) -> Bool {
        let s = latex
        for env in Self.environments {
            if s.contains("\\begin{\(env)}") || s.contains("\\begin {\(env)}") {
                if env == "array" { return s.contains("&") || s.contains("\\\\") }
                return true
            }
        }
        return false
    }

    /// 这条求解结果是不是矩阵菜单算出来的。改式子、重新算时用它找回原来的操作。
    public static func action(for operation: Solution.Operation) -> MatrixAction? {
        switch operation {
        case .matrix: return .calculate
        case .inverse: return .inverse
        case .determinant: return .determinant
        case .transform: return .transform
        default: return nil
        }
    }

    public static func solve(_ latex: String, action: MatrixAction) -> Solution {
        let operation = Self.operation(action)
        let source = preprocess(latex)
        guard contains(latex) || contains(source) else {
            return outcome(source.isEmpty ? latex : source, nil, "没有认出矩阵", conclusive: false, operation: operation)
        }
        let (name, body) = definition(source)
        do {
            let expr = try Parser(body).parse()
            let value = try expr.evaluate()
            return try present(expr, value, name: name, action: action, operation: operation)
        } catch let problem as MatrixProblem {
            return outcome(source.isEmpty ? latex : source, nil, problem.message, conclusive: problem.conclusive, operation: operation)
        } catch {
            return outcome(source.isEmpty ? latex : source, nil, "没算出来", conclusive: false, operation: operation)
        }
    }

    /// 这一段算出来是不是一个 2×2 的数字矩阵（「看变换」用）。A = … 的名字不算在里面。
    public static func linearMap(_ latex: String) -> LinearMap2? {
        let source = preprocess(latex)
        guard contains(latex) || contains(source), let expr = try? Parser(definition(source).body).parse(),
              case .matrix(let m)? = try? expr.evaluate(), m.m == 2, m.n == 2 else { return nil }
        return LinearMap2(a: m.rows[0][0].doubleValue, b: m.rows[0][1].doubleValue,
                          c: m.rows[1][0].doubleValue, d: m.rows[1][1].doubleValue)
    }

    /// A = … 左边的名字；没写名字时为 nil。
    public static func name(_ latex: String) -> String? {
        definition(preprocess(latex)).name
    }

    /// 「看变换」里拖了基向量：式子改写成新的矩阵（名字留着）。
    public static func rewrite(_ latex: String, with map: LinearMap2) -> String {
        (name(latex).map { $0 + " = " } ?? "") + map.latex
    }

    fileprivate static let environments = ["pmatrix", "bmatrix", "Bmatrix", "vmatrix", "Vmatrix", "smallmatrix", "matrix", "array"]

    private static func operation(_ action: MatrixAction) -> Solution.Operation {
        switch action {
        case .calculate: return .matrix
        case .inverse: return .inverse
        case .determinant: return .determinant
        case .transform: return .transform
        }
    }

    /// 「A = …」：左边是一个字母（可以带下标、撇号），右边是要算的矩阵式子。别的写法原样返回。
    static func definition(_ source: String) -> (name: String?, body: String) {
        let chars = Array(source)
        var depth = 0
        for (k, c) in chars.enumerated() {
            if c == "{" || c == "(" { depth += 1 } else if c == "}" || c == ")" { depth -= 1 }
            guard c == "=", depth == 0 else { continue }
            let lhs = String(chars[..<k]).trimmingCharacters(in: .whitespaces)
            let rhs = String(chars[(k + 1)...]).trimmingCharacters(in: .whitespaces)
            guard !rhs.isEmpty, lhs.range(of: #"^[A-Za-z](_\{?[A-Za-z0-9]+\}?)?'*$"#, options: .regularExpression) != nil else {
                return (nil, source)
            }
            return (lhs, rhs)
        }
        return (nil, source)
    }

    private static func present(_ expr: Expr, _ value: Value, name: String?, action: MatrixAction,
                                operation: Solution.Operation) throws -> Solution {
        // 写了名字：左边照写「A = …」；只写了一个矩阵、不用算时不再「= 同一个矩阵」
        let input = name.map { $0 + " = " + expr.latex() } ?? expr.latex()
        let literal = expr.isLiteral
        switch action {
        case .calculate:
            if name != nil, literal { return outcome(input, nil, nil, conclusive: false, operation: operation) }
            return outcome(input, value.latex, nil, conclusive: false, operation: operation)
        case .inverse:
            guard case .matrix(let m) = value else {
                throw MatrixProblem("这是一个数，没有逆矩阵", conclusive: true)
            }
            let inv = try m.inverse()
            if let name {
                return outcome(input, inv.latex, nil, conclusive: false, operation: operation, relation: ",\\; " + name + "^{-1} =")
            }
            return outcome("\\left(" + expr.latex() + "\\right)^{-1}", inv.latex, nil, conclusive: false, operation: operation)
        case .determinant:
            if case .scalar(let r) = value {
                return outcome(input, RationalText.latex(r), nil, conclusive: false, operation: operation)
            }
            guard case .matrix(let m) = value else {
                throw MatrixProblem("没有求出行列式", conclusive: false)
            }
            let d = try m.determinant()
            if let name {
                return outcome(input, RationalText.latex(d), nil, conclusive: false, operation: operation, relation: ",\\; \\det " + name + " =")
            }
            let det = expr.isDet ? expr.latex() : "\\det\\left(" + expr.latex() + "\\right)"
            return outcome(det, RationalText.latex(d), nil, conclusive: false, operation: operation)
        case .transform:
            guard case .matrix(let m) = value else {
                throw MatrixProblem("这是一个数，看不了变换", conclusive: true)
            }
            guard m.m == 2, m.n == 2 else {
                throw MatrixProblem("看变换只支持 2×2 矩阵（这是 \(m.shapeText())）", conclusive: true)
            }
            return outcome(input, literal ? nil : m.latex, nil, conclusive: false, operation: operation)
        }
    }

    private static func outcome(_ input: String, _ result: String?, _ note: String?, conclusive: Bool,
                                operation: Solution.Operation, relation: String = "=") -> Solution {
        Solution(input: input, result: result, relation: relation, note: note, conclusive: conclusive,
                 operation: operation, references: [], hint: nil)
    }
}

private struct MatrixProblem: Error {
    var message: String
    var conclusive: Bool
    init(_ message: String, conclusive: Bool) {
        self.message = message
        self.conclusive = conclusive
    }
}

private enum RationalText {
    static func latex(_ r: Rational) -> String {
        guard r.isValid else { return "?" }
        if r.isZero { return "0" }
        let sign = r.isNegative ? "-" : ""
        let a = r.abs
        if a.d == 1 { return sign + "\(a.n)" }
        return sign + "\\frac{\(a.n)}{\(a.d)}"
    }
}

private struct Matrix: Equatable {
    var rows: [[Rational]]

    var m: Int { rows.count }
    var n: Int { rows.first?.count ?? 0 }
    var isSquare: Bool { m > 0 && m == n }

    var latex: String {
        let body = rows.map { $0.map(RationalText.latex).joined(separator: " & ") }.joined(separator: " \\\\ ")
        return "\\begin{pmatrix}" + body + "\\end{pmatrix}"
    }

    func shapeText() -> String { "\(m)×\(n)" }

    static func add(_ a: Matrix, _ b: Matrix) throws -> Matrix {
        guard a.m == b.m, a.n == b.n, a.n > 0 else {
            throw MatrixProblem("不能相加：一个是 \(a.shapeText())，另一个是 \(b.shapeText())", conclusive: true)
        }
        return Matrix(rows: try combine(a, b, subtract: false))
    }

    static func sub(_ a: Matrix, _ b: Matrix) throws -> Matrix {
        guard a.m == b.m, a.n == b.n, a.n > 0 else {
            throw MatrixProblem("不能相减：一个是 \(a.shapeText())，另一个是 \(b.shapeText())", conclusive: true)
        }
        return Matrix(rows: try combine(a, b, subtract: true))
    }

    private static func combine(_ a: Matrix, _ b: Matrix, subtract: Bool) throws -> [[Rational]] {
        var out: [[Rational]] = []
        for i in 0..<a.m {
            var row: [Rational] = []
            for j in 0..<a.n {
                let x = a.rows[i][j]
                let y = b.rows[i][j]
                row.append(try Self.check(subtract ? x - y : x + y))
            }
            out.append(row)
        }
        return out
    }

    static func mul(_ a: Matrix, _ b: Matrix) throws -> Matrix {
        guard a.n == b.m, a.m > 0, b.n > 0 else {
            throw MatrixProblem("不能相乘：一个是 \(a.shapeText())，另一个是 \(b.shapeText())", conclusive: true)
        }
        var out: [[Rational]] = []
        for i in 0..<a.m {
            var row: [Rational] = []
            for j in 0..<b.n {
                var sum = Rational.zero
                for k in 0..<a.n { sum = sum + a.rows[i][k] * b.rows[k][j] }
                row.append(try Self.check(sum))
            }
            out.append(row)
        }
        return Matrix(rows: out)
    }

    func scaled(_ by: Rational) throws -> Matrix {
        var out: [[Rational]] = []
        for row in rows {
            var next: [Rational] = []
            for value in row { next.append(try Self.check(value * by)) }
            out.append(next)
        }
        return Matrix(rows: out)
    }

    func negated() throws -> Matrix { try scaled(-Rational.one) }

    func transposed() -> Matrix {
        guard m > 0, n > 0 else { return self }
        var out = Array(repeating: Array(repeating: Rational.zero, count: m), count: n)
        for i in 0..<m { for j in 0..<n { out[j][i] = rows[i][j] } }
        return Matrix(rows: out)
    }

    func determinant() throws -> Rational {
        guard isSquare else { throw MatrixProblem("不是方阵，没有行列式", conclusive: true) }
        var a = rows
        var det = Rational.one
        let n = m
        for k in 0..<n {
            var pivot = k
            while pivot < n, a[pivot][k].isZero { pivot += 1 }
            if pivot == n { return .zero }
            if pivot != k {
                a.swapAt(pivot, k)
                det = -det
            }
            let p = a[k][k]
            det = try Self.check(det * p)
            for i in (k + 1)..<n {
                let f = try Self.check(a[i][k] / p)
                for j in k..<n {
                    a[i][j] = try Self.check(a[i][j] - f * a[k][j])
                }
            }
        }
        return det
    }

    func inverse() throws -> Matrix {
        guard isSquare else { throw MatrixProblem("不是方阵，没有逆矩阵", conclusive: true) }
        let n = m
        var a = rows
        var inv = (0..<n).map { i in (0..<n).map { j in i == j ? Rational.one : Rational.zero } }
        for k in 0..<n {
            var pivot = k
            while pivot < n, a[pivot][k].isZero { pivot += 1 }
            if pivot == n { throw MatrixProblem("行列式为 0，没有逆矩阵", conclusive: true) }
            if pivot != k {
                a.swapAt(pivot, k)
                inv.swapAt(pivot, k)
            }
            let p = a[k][k]
            for j in 0..<n {
                a[k][j] = try Self.check(a[k][j] / p)
                inv[k][j] = try Self.check(inv[k][j] / p)
            }
            for i in 0..<n where i != k {
                let f = a[i][k]
                if f.isZero { continue }
                for j in 0..<n {
                    a[i][j] = try Self.check(a[i][j] - f * a[k][j])
                    inv[i][j] = try Self.check(inv[i][j] - f * inv[k][j])
                }
            }
        }
        return Matrix(rows: inv)
    }

    fileprivate static func check(_ r: Rational) throws -> Rational {
        guard r.isValid else { throw MatrixProblem("数字太大，算不下", conclusive: false) }
        return r
    }
}

private enum Value: Equatable {
    case matrix(Matrix)
    case scalar(Rational)

    var latex: String {
        switch self {
        case .matrix(let m): return m.latex
        case .scalar(let r): return RationalText.latex(r)
        }
    }
}

private indirect enum Expr: Equatable {
    case matrix(Matrix)
    case scalar(Rational)
    case add(Expr, Expr)
    case sub(Expr, Expr)
    case mul(Expr, Expr)
    case neg(Expr)
    case inv(Expr)
    case transpose(Expr)
    case det(Expr)

    var isDet: Bool {
        if case .det = self { return true }
        return false
    }

    /// 只写了一个矩阵，没有要算的。
    var isLiteral: Bool {
        if case .matrix = self { return true }
        return false
    }

    func evaluate() throws -> Value {
        switch self {
        case .matrix(let m): return .matrix(m)
        case .scalar(let r): return .scalar(r)
        case .add(let a, let b): return try Self.combine(a, b, add: true)
        case .sub(let a, let b): return try Self.combine(a, b, add: false)
        case .mul(let a, let b): return try Self.multiply(a, b)
        case .neg(let a):
            switch try a.evaluate() {
            case .scalar(let r): return .scalar(try Matrix.check(-r))
            case .matrix(let m): return .matrix(try m.negated())
            }
        case .inv(let a):
            guard case .matrix(let m) = try a.evaluate() else {
                throw MatrixProblem("这是一个数，没有逆矩阵", conclusive: true)
            }
            return .matrix(try m.inverse())
        case .transpose(let a):
            guard case .matrix(let m) = try a.evaluate() else {
                throw MatrixProblem("数没有转置", conclusive: true)
            }
            return .matrix(m.transposed())
        case .det(let a):
            guard case .matrix(let m) = try a.evaluate() else {
                throw MatrixProblem("这是一个数，没有行列式", conclusive: true)
            }
            return .scalar(try m.determinant())
        }
    }

    func latex() -> String { latex(prec: 0) }

    private func latex(prec: Int) -> String {
        switch self {
        case .matrix(let m): return m.latex
        case .scalar(let r): return RationalText.latex(r)
        case .add(let a, let b):
            return wrap(prec, 1, a.latex(prec: 1) + "+" + b.latex(prec: 1))
        case .sub(let a, let b):
            return wrap(prec, 1, a.latex(prec: 1) + "-" + b.latex(prec: 2))
        case .mul(let a, let b):
            return wrap(prec, 2, a.latex(prec: 2) + " " + b.latex(prec: 2))
        case .neg(let a):
            return wrap(prec, 3, "-" + a.latex(prec: 3))
        case .inv(let a):
            return "\\left(" + a.latex(prec: 0) + "\\right)^{-1}"
        case .transpose(let a):
            return "\\left(" + a.latex(prec: 0) + "\\right)^{T}"
        case .det(let a):
            return "\\det\\left(" + a.latex(prec: 0) + "\\right)"
        }
    }

    private func wrap(_ parent: Int, _ mine: Int, _ body: String) -> String {
        parent > mine ? "\\left(" + body + "\\right)" : body
    }

    private static func combine(_ a: Expr, _ b: Expr, add: Bool) throws -> Value {
        switch (try a.evaluate(), try b.evaluate()) {
        case (.scalar(let x), .scalar(let y)):
            return .scalar(try Matrix.check(add ? x + y : x - y))
        case (.matrix(let x), .matrix(let y)):
            return .matrix(try (add ? Matrix.add(x, y) : Matrix.sub(x, y)))
        default:
            throw MatrixProblem(add ? "数和矩阵不能相加" : "数和矩阵不能相减", conclusive: true)
        }
    }

    private static func multiply(_ a: Expr, _ b: Expr) throws -> Value {
        switch (try a.evaluate(), try b.evaluate()) {
        case (.scalar(let x), .scalar(let y)):
            return .scalar(try Matrix.check(x * y))
        case (.scalar(let x), .matrix(let y)):
            return .matrix(try y.scaled(x))
        case (.matrix(let x), .scalar(let y)):
            return .matrix(try x.scaled(y))
        case (.matrix(let x), .matrix(let y)):
            return .matrix(try Matrix.mul(x, y))
        }
    }
}

private enum Tok: Equatable {
    case matrix(Matrix)
    case num(Rational)
    case plus, minus, times, lparen, rparen, inv, transpose, det
}

private struct Parser {
    private let chars: [Character]
    private var i = 0

    init(_ source: String) {
        chars = Array(preprocess(source))
    }

    func parse() throws -> Expr {
        var p = self
        try p.prepare()
        let expr = try p.parseExpr()
        guard p.tokenIndex >= p.tokens.count else { throw MatrixProblem("式子没写完", conclusive: false) }
        return expr
    }

    private mutating func parseExpr() throws -> Expr {
        var left = try parseTerm()
        while true {
            if eat(.plus) { left = .add(left, try parseTerm()) }
            else if eat(.minus) { left = .sub(left, try parseTerm()) }
            else { break }
        }
        return left
    }

    private mutating func parseTerm() throws -> Expr {
        var left = try parseUnary()
        while eat(.times) { left = .mul(left, try parseUnary()) }
        return left
    }

    private mutating func parseUnary() throws -> Expr {
        if eat(.plus) { return try parseUnary() }
        if eat(.minus) { return .neg(try parseUnary()) }
        if eat(.det) { return .det(try parseUnary()) }
        return try parsePostfix()
    }

    private mutating func parsePostfix() throws -> Expr {
        var left = try parseAtom()
        while true {
            if eat(.inv) { left = .inv(left) }
            else if eat(.transpose) { left = .transpose(left) }
            else { break }
        }
        return left
    }

    private mutating func parseAtom() throws -> Expr {
        if eat(.lparen) {
            let inner = try parseExpr()
            guard eat(.rparen) else { throw MatrixProblem("括号没写完", conclusive: false) }
            return inner
        }
        guard let t = pop() else { throw MatrixProblem("式子没写完", conclusive: false) }
        switch t {
        case .matrix(let m): return .matrix(m)
        case .num(let r): return .scalar(r)
        default: throw MatrixProblem("看不懂这一段矩阵式子", conclusive: false)
        }
    }

    private mutating func eat(_ kind: Tok) -> Bool {
        guard tokens.indices.contains(tokenIndex) else { return false }
        let t = tokens[tokenIndex]
        let same: Bool
        switch (t, kind) {
        case (.plus, .plus), (.minus, .minus), (.times, .times), (.lparen, .lparen), (.rparen, .rparen),
             (.inv, .inv), (.transpose, .transpose), (.det, .det):
            same = true
        default:
            same = false
        }
        if same { tokenIndex += 1 }
        return same
    }

    private mutating func pop() -> Tok? {
        guard tokens.indices.contains(tokenIndex) else { return nil }
        let t = tokens[tokenIndex]
        tokenIndex += 1
        return t
    }

    private var tokens: [Tok] = []
    private var tokenIndex = 0

    private mutating func prepare() throws {
        var raw: [Tok] = []
        while i < chars.count {
            skipSpace()
            if i >= chars.count { break }
            if chars[i] == "=" { break }
            if chars[i] == "\\", i + 1 < chars.count, chars[i + 1] == " ", i == 0 || chars[i - 1] != "\\" {
                i += 2
                continue
            }
            if consume("\\begin") {
                raw.append(.matrix(try readMatrix()))
                continue
            }
            if let r = try readFraction() {
                raw.append(.num(r))
                continue
            }
            if consume("\\left") || consume("\\right") {
                skipDelimiter()
                continue
            }
            if consume("\\times") || consume("\\cdot") || consume("\\ast") {
                raw.append(.times)
                continue
            }
            if consume("\\det") {
                raw.append(.det)
                continue
            }
            if consume("\\operatorname{") || consume("\\mathrm{") || consume("\\text{") {
                let inner = try readGroupBody()
                if inner.trimmingCharacters(in: .whitespaces) == "det" {
                    raw.append(.det)
                } else {
                    raw.append(.num(try RationalReader.read(inner)))
                }
                continue
            }
            if consume("\\displaystyle") || consume("\\,") || consume("\\;") || consume("\\:") || consume("\\!") || consume("\\quad") || consume("\\qquad") {
                continue
            }
            if chars[i] == "\\" {
                let name = commandName()
                throw MatrixProblem(name.isEmpty ? "看不懂这个式子" : "看不懂「\\\(name)」", conclusive: false)
            }
            if chars[i].isNumber || chars[i] == "." {
                raw.append(.num(try readDecimal()))
                continue
            }
            switch chars[i] {
            case "+": raw.append(.plus); i += 1
            case "-": raw.append(.minus); i += 1
            case "*": raw.append(.times); i += 1
            case "(": raw.append(.lparen); i += 1
            case ")": raw.append(.rparen); i += 1
            case "^": raw.append(try readPower()); i += 0
            default:
                throw MatrixProblem("看不懂「\(chars[i])」", conclusive: false)
            }
        }
        tokens = insertTimes(raw)
        guard !tokens.isEmpty else { throw MatrixProblem("没有写出矩阵", conclusive: false) }
        guard tokens.contains(where: { if case .matrix = $0 { return true }; return false }) else {
            throw MatrixProblem("没有写出矩阵", conclusive: false)
        }
    }

    private func insertTimes(_ raw: [Tok]) -> [Tok] {
        var out: [Tok] = []
        for t in raw {
            if let prev = out.last, endsValue(prev), startsValue(t) { out.append(.times) }
            out.append(t)
        }
        return out
    }

    private func endsValue(_ t: Tok) -> Bool {
        switch t {
        case .matrix, .num, .rparen, .inv, .transpose: return true
        default: return false
        }
    }

    private func startsValue(_ t: Tok) -> Bool {
        switch t {
        case .matrix, .num, .lparen, .det: return true
        default: return false
        }
    }

    private mutating func readMatrix() throws -> Matrix {
        let name = try readEnvName()
        guard MatrixMath.environments.contains(name) else {
            throw MatrixProblem("看不懂 \\begin{\(name)}", conclusive: false)
        }
        let end = "\\end{\(name)}"
        let endSpaced = "\\end {\(name)}"
        guard let close = rangeOf(end) ?? rangeOf(endSpaced) else {
            throw MatrixProblem("矩阵没写完", conclusive: false)
        }
        let body = String(chars[i..<close.lowerBound])
        i = close.upperBound
        return try MatrixReader(body).matrix()
    }

    private mutating func readEnvName() throws -> String {
        skipSpace()
        guard i < chars.count, chars[i] == "{" else { throw MatrixProblem("矩阵没写完", conclusive: false) }
        i += 1
        let name = readUntil("}")
        guard i < chars.count, chars[i] == "}" else { throw MatrixProblem("矩阵没写完", conclusive: false) }
        i += 1
        return name
    }

    private mutating func readFraction() throws -> Rational? {
        let commands = ["\\dfrac", "\\tfrac", "\\frac"]
        guard commands.contains(where: { hasPrefix($0) }) else { return nil }
        if consume("\\dfrac") || consume("\\tfrac") || consume("\\frac") {
            skipSpace()
            guard consume("{") else { throw MatrixProblem("分数没写完", conclusive: false) }
            let num = try readGroupBody()
            skipSpace()
            guard consume("{") else { throw MatrixProblem("分数没写完", conclusive: false) }
            let den = try readGroupBody()
            let a = try RationalReader.read(num)
            let b = try RationalReader.read(den)
            guard !b.isZero else { throw MatrixProblem("分母是 0", conclusive: true) }
            let q = a / b
            guard q.isValid else { throw MatrixProblem("数字太大，算不下", conclusive: false) }
            return q
        }
        return nil
    }

    /// `{` 已经被吃掉。读到配平的 `}`，返回里面的字。
    private mutating func readGroupBody() throws -> String {
        var depth = 1
        let start = i
        while i < chars.count {
            if chars[i] == "{" { depth += 1 }
            else if chars[i] == "}" {
                depth -= 1
                if depth == 0 {
                    let body = String(chars[start..<i])
                    i += 1
                    return body
                }
            }
            i += 1
        }
        throw MatrixProblem("括号没写完", conclusive: false)
    }

    private mutating func readPower() throws -> Tok {
        i += 1
        skipSpace()
        let braced = consume("{")
        skipSpace()
        let tok: Tok
        if consume("\\top") || consume("\\intercal") || consume("\\mathrm{T}") || consume("T") || consume("t") {
            tok = .transpose
        } else if consume("-") {
            skipSpace()
            guard consume("1") else { throw MatrixProblem("矩阵的指数只认 -1 和 T", conclusive: false) }
            tok = .inv
        } else {
            throw MatrixProblem("矩阵的指数只认 -1 和 T", conclusive: false)
        }
        if braced {
            skipSpace()
            guard consume("}") else { throw MatrixProblem("指数的括号没写完", conclusive: false) }
        }
        return tok
    }

    private mutating func readDecimal() throws -> Rational {
        var text = ""
        var dot = false
        while i < chars.count {
            let c = chars[i]
            if c.isNumber { text.append(c); i += 1 }
            else if c == ".", !dot { dot = true; text.append(c); i += 1 }
            else { break }
        }
        return try RationalReader.decimal(text)
    }

    private mutating func skipDelimiter() {
        skipSpace()
        if consume("\\{") || consume("\\}") || consume("\\|") || consume(".") { return }
        if i < chars.count, "()[]|".contains(chars[i]) {
            // ( ) 留给分组；[ ] | . 只是定界符
            if chars[i] == "(" || chars[i] == ")" { return }
            i += 1
        }
    }

    private mutating func skipSpace() {
        while i < chars.count, chars[i] == " " || chars[i] == "\n" || chars[i] == "\t" { i += 1 }
    }

    private func snippet() -> String {
        let end = min(chars.count, i + 8)
        return String(chars[i..<end])
    }

    private func hasPrefix(_ s: String) -> Bool {
        let a = Array(s)
        guard i + a.count <= chars.count else { return false }
        return Array(chars[i..<(i + a.count)]) == a
    }

    private mutating func consume(_ s: String) -> Bool {
        guard hasPrefix(s) else { return false }
        i += s.count
        return true
    }

    private mutating func commandName() -> String {
        var j = i + 1
        var name = ""
        while j < chars.count, chars[j].isLetter { name.append(chars[j]); j += 1 }
        return name
    }

    private func rangeOf(_ needle: String) -> Range<Int>? {
        let n = Array(needle)
        guard !n.isEmpty, i < chars.count else { return nil }
        var k = i
        while k + n.count <= chars.count {
            if Array(chars[k..<(k + n.count)]) == n { return k..<(k + n.count) }
            k += 1
        }
        return nil
    }

    private mutating func readUntil(_ stop: Character) -> String {
        var out = ""
        while i < chars.count, chars[i] != stop {
            out.append(chars[i])
            i += 1
        }
        return out
    }
}

private struct MatrixReader {
    let body: String
    init(_ body: String) { self.body = body }

    func matrix() throws -> Matrix {
        var text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("{") {
            text = try dropGroup(text)
        }
        text = text.replacingOccurrences(of: "\\hline", with: " ")
        let rawRows = splitTop(text, separators: ["\\\\", "\\cr", "\\newline"])
        var rows: [[Rational]] = []
        for raw in rawRows {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            let cells = splitTop(trimmed, separators: ["&"])
            if cells.isEmpty { throw MatrixProblem("矩阵是空的", conclusive: false) }
            var parsed: [Rational] = []
            for cell in cells {
                let t = cell.trimmingCharacters(in: .whitespacesAndNewlines)
                if t.isEmpty { throw MatrixProblem("矩阵里有一格是空的", conclusive: false) }
                parsed.append(try RationalReader.read(t))
            }
            rows.append(parsed)
        }
        guard let width = rows.first?.count, width > 0 else { throw MatrixProblem("矩阵是空的", conclusive: false) }
        guard rows.allSatisfy({ $0.count == width }) else {
            throw MatrixProblem("矩阵每一行的列数要一样", conclusive: false)
        }
        guard rows.count <= 6, width <= 6 else {
            throw MatrixProblem("矩阵太大，暂时只算到 6×6", conclusive: false)
        }
        return Matrix(rows: rows)
    }

    private func dropGroup(_ text: String) throws -> String {
        var depth = 0
        let chars = Array(text)
        for (k, c) in chars.enumerated() {
            if c == "{" { depth += 1 }
            else if c == "}" {
                depth -= 1
                if depth == 0 { return String(chars[(k + 1)...]) }
            }
        }
        throw MatrixProblem("矩阵没写完", conclusive: false)
    }

    private func splitTop(_ text: String, separators: [String]) -> [String] {
        let chars = Array(text)
        var parts: [String] = []
        var current = ""
        var depth = 0
        var k = 0
        while k < chars.count {
            if chars[k] == "{" { depth += 1 }
            else if chars[k] == "}" { depth = max(0, depth - 1) }
            if depth == 0, let sep = separators.first(where: { has(chars, k, $0) }) {
                parts.append(current)
                current = ""
                k += sep.count
                continue
            }
            current.append(chars[k])
            k += 1
        }
        parts.append(current)
        return parts
    }

    private func has(_ chars: [Character], _ k: Int, _ s: String) -> Bool {
        let a = Array(s)
        guard k + a.count <= chars.count else { return false }
        return Array(chars[k..<(k + a.count)]) == a
    }
}

private struct RationalReader {
    private let chars: [Character]
    private var i = 0

    init(_ source: String) {
        chars = Array(preprocess(source))
    }

    static func read(_ source: String) throws -> Rational {
        var reader = RationalReader(source)
        return try reader.parse()
    }

    static func decimal(_ text: String) throws -> Rational {
        try read(text)
    }

    mutating func parse() throws -> Rational {
        let v = try expr()
        skip()
        guard i >= chars.count else { throw MatrixProblem("矩阵元素必须是常数", conclusive: false) }
        guard v.isValid else { throw MatrixProblem("数字太大，算不下", conclusive: false) }
        return v
    }

    private mutating func expr() throws -> Rational {
        var v = try term()
        while true {
            skip()
            if consume("+") { v = v + (try term()) }
            else if consume("-") { v = v - (try term()) }
            else { break }
        }
        return v
    }

    private mutating func term() throws -> Rational {
        var v = try unary()
        while true {
            skip()
            if consume("*") || consume("\\times") || consume("\\cdot") { v = v * (try unary()) }
            else if consume("/") { 
                let d = try unary()
                guard !d.isZero else { throw MatrixProblem("分母是 0", conclusive: true) }
                v = v / d
            } else { break }
        }
        return v
    }

    private mutating func unary() throws -> Rational {
        skip()
        if consume("+") { return try unary() }
        if consume("-") { return -(try unary()) }
        return try primary()
    }

    private mutating func primary() throws -> Rational {
        skip()
        if consume("\\dfrac") || consume("\\tfrac") || consume("\\frac") {
            skip()
            guard consume("{") else { throw MatrixProblem("分数没写完", conclusive: false) }
            let num = try group()
            skip()
            guard consume("{") else { throw MatrixProblem("分数没写完", conclusive: false) }
            let den = try group()
            let a = try RationalReader.read(num)
            let b = try RationalReader.read(den)
            guard !b.isZero else { throw MatrixProblem("分母是 0", conclusive: true) }
            return a / b
        }
        if consume("(") {
            let v = try expr()
            skip()
            guard consume(")") else { throw MatrixProblem("括号没写完", conclusive: false) }
            return v
        }
        if consume("\\mathrm{") || consume("\\text{") {
            return try RationalReader.read(try group())
        }
        guard i < chars.count, chars[i].isNumber || chars[i] == "." else {
            throw MatrixProblem("矩阵元素必须是常数", conclusive: false)
        }
        return try number()
    }

    private mutating func group() throws -> String {
        var depth = 1
        var out = ""
        while i < chars.count {
            let c = chars[i]
            i += 1
            if c == "{" { depth += 1; out.append(c) }
            else if c == "}" {
                depth -= 1
                if depth == 0 { return out }
                out.append(c)
            } else { out.append(c) }
        }
        throw MatrixProblem("括号没写完", conclusive: false)
    }

    private mutating func number() throws -> Rational {
        var text = ""
        var dot = false
        while i < chars.count {
            let c = chars[i]
            if c.isNumber { text.append(c); i += 1 }
            else if c == ".", !dot { dot = true; text.append(c); i += 1 }
            else { break }
        }
        let digits = text.filter { $0.isNumber }
        if digits.count > Limits.maxDigits { throw MatrixProblem("数字太长", conclusive: false) }
        if !text.contains(".") {
            guard let n = Int(text) else { throw MatrixProblem("数字太大，算不下", conclusive: false) }
            return Rational(n)
        }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        let whole = parts.first.map(String.init) ?? "0"
        let frac = parts.count > 1 ? String(parts[1]) : ""
        let combined = (whole.isEmpty ? "0" : whole) + frac
        guard let n = Int(combined.isEmpty ? "0" : combined) else { throw MatrixProblem("数字太大，算不下", conclusive: false) }
        var d = 1
        for _ in frac { 
            let (next, overflow) = d.multipliedReportingOverflow(by: 10)
            if overflow { throw MatrixProblem("数字太大，算不下", conclusive: false) }
            d = next
        }
        return Rational(n, max(d, 1))
    }

    private mutating func skip() {
        while i < chars.count, chars[i] == " " || chars[i] == "\n" || chars[i] == "\t" { i += 1 }
    }

    private mutating func consume(_ s: String) -> Bool {
        let a = Array(s)
        guard i + a.count <= chars.count, Array(chars[i..<(i + a.count)]) == a else { return false }
        i += a.count
        return true
    }
}

private func preprocess(_ raw: String) -> String {
    var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    // 不要动 "\\ "：那是换行 \\ 再加空格，不是间距命令 \ （反斜杠加空格）。
    let swaps = [("\\displaystyle", ""), ("\\,", " "), ("\\;", " "), ("\\:", " "), ("\\!", ""),
                 ("\\quad", " "), ("\\qquad", " "), ("−", "-"), ("–", "-"), ("—", "-")]
    for (a, b) in swaps { s = s.replacingOccurrences(of: a, with: b) }
    if s.hasPrefix("$$"), s.hasSuffix("$$"), s.count >= 4 {
        s = String(s.dropFirst(2).dropLast(2))
    } else if s.hasPrefix("$"), s.hasSuffix("$"), s.count >= 2 {
        s = String(s.dropFirst().dropLast())
    }
    s = stripWrapper(s.trimmingCharacters(in: .whitespacesAndNewlines))
    s = stripCommasInsideMatrices(s)
    return s.trimmingCharacters(in: .whitespacesAndNewlines)
}

/// 识别器有时在矩阵里多写逗号（常见是下一行开头的 `,3`）。逗号不是矩阵元素，丢掉再算、再显示。
private func stripCommasInsideMatrices(_ s: String) -> String {
    var out = ""
    var i = s.startIndex
    while i < s.endIndex {
        guard s[i] == "\\" else {
            out.append(s[i])
            i = s.index(after: i)
            continue
        }
        let matched = MatrixMath.environments.first { env in s[i...].hasPrefix("\\begin{\(env)}") }
        guard let env = matched,
              let bodyStart = s.index(i, offsetBy: "\\begin{\(env)}".count, limitedBy: s.endIndex),
              let end = s.range(of: "\\end{\(env)}", range: bodyStart..<s.endIndex) else {
            out.append(s[i])
            i = s.index(after: i)
            continue
        }
        out.append(contentsOf: s[i..<bodyStart])
        out.append(contentsOf: s[bodyStart..<end.lowerBound].filter { $0 != "," })
        out.append(contentsOf: s[end])
        i = end.upperBound
    }
    return out
}

private func stripWrapper(_ s: String) -> String {
    let wrappers = ["aligned", "align*", "align", "equation*", "equation", "gather*", "gather", "gathered", "split"]
    for env in wrappers {
        let open = "\\begin{\(env)}"
        let close = "\\end{\(env)}"
        if s.hasPrefix(open), s.hasSuffix(close), s.count > open.count + close.count {
            return String(s.dropFirst(open.count).dropLast(close.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
    return s
}

