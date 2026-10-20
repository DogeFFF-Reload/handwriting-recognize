//
//  Engine.swift
//  MathEngine
//
//  批注（错在哪一项）、函数场景（滑条与极值）、矩阵、积分、推导等价、几何关系。
//  和对错有关的一切都在这里，大模型不参与。
//
//  v3（2026-10-20）：Defect 带 explanation / expectedPow（direct 模式要用）；
//  极值支持导数三次以上（数值求根）；积分定积分改为精确有理数；矩阵说明写出行乘列算式。
//

import Foundation

// MARK: - 错误码

public enum DefectKind: String {
    case wrongTerm = "wrong_term"
    case wrongCoefficient = "wrong_coefficient"
    case wrongSign = "wrong_sign"
    case missingTerm = "missing_term"
    case extraTerm = "extra_term"
    case notDerivative = "not_derivative"
    case notEquivalent = "not_equivalent"
    case wrongElement = "wrong_element"
    case integrandMismatch = "integrand_mismatch"
    case parseError = "parse_error"
}

public struct Defect: Equatable {
    public var kind: DefectKind
    /// 学生原文里的那一段（给 Flash / 笔画包围盒用）
    public var wrongLatex: String?
    /// 正确项。**只用于后端生成提示和测试，不进客户端的 Annotation**
    public var expectedLatex: String?
    /// 在 `body` 字符数组里的区间
    public var span: Range<Int>?
    public var pow: Int?
    public var row: Int?
    public var col: Int?
    /// 正确项的幂次（wrong_term 时 pow 是学生那一项的幂，和它不同）。生成说明要靠它找回原式那一项
    public var expectedPow: Int?
    /// direct 模式下的一句说明（确定性模板，不调模型）。socratic 模式下 API 层不下发
    public var explanation: String?

    public init(kind: DefectKind,
                wrongLatex: String? = nil,
                expectedLatex: String? = nil,
                span: Range<Int>? = nil,
                pow: Int? = nil,
                row: Int? = nil,
                col: Int? = nil,
                expectedPow: Int? = nil,
                explanation: String? = nil) {
        self.kind = kind
        self.wrongLatex = wrongLatex
        self.expectedLatex = expectedLatex
        self.span = span
        self.pow = pow
        self.row = row
        self.col = col
        self.expectedPow = expectedPow
        self.explanation = explanation
    }

    /// 确定性兜底提示：模型超时/断网时直接用，**不许包含正确答案**
    public func fallbackHint() -> String {
        switch kind {
        case .wrongTerm: return "\(wrongLatex ?? "这一项") 这一项对不上：先单独对它求一次导，会剩下什么？"
        case .wrongCoefficient: return "\(wrongLatex ?? "这一项") 的系数再算一次：指数乘到前面之后，还剩多少？"
        case .wrongSign: return "先只看符号：\(wrongLatex ?? "这一项") 到底该是正还是负？"
        case .missingTerm: return "这一行比原式少了一项，原式里还有哪一项没求导？"
        case .extraTerm: return "\(wrongLatex ?? "这一项") 是多出来的，它是从原式哪一项变过来的？"
        case .notDerivative: return "右边写的好像不是导数，先把求导这一步写出来。"
        case .notEquivalent: return "这两步之间是不是乘过同一个式子？它有可能等于 0 吗？"
        case .wrongElement: return "第 \(row ?? 0) 行第 \(col ?? 0) 列：行乘列时每一项都加进去了吗？"
        case .integrandMismatch: return "把这一项的结果再求导一次，看能不能回到被积函数。"
        case .parseError: return "这一行没读出来，点一下把它改正过来。"
        }
    }
}

// MARK: - LaTeX 渲染（只给后端和测试用）

public enum LatexRender {
    public static func term(coef: Rational, pow: Int) -> String {
        if pow == 0 { return coef.d == 1 ? "\(coef.n)" : "\\frac{\(coef.n)}{\(coef.d)}" }
        let body = pow == 1 ? "x" : "x^{\(pow)}"
        if coef == Rational(1) { return body }
        if coef == Rational(-1) { return "-" + body }
        if coef.d == 1 { return "\(coef.n)" + body }
        return "\\frac{\(coef.n)}{\(coef.d)}" + body
    }

    /// 契约风格的单项：`-3`、`3x^2`、`x`（不带花括号）
    public static func compactTerm(coef: Rational, pow: Int) -> String {
        LatexText.compactExponents(term(coef: coef, pow: pow))
    }

    public static func poly(_ p: Poly) -> String {
        if p.isZero { return "0" }
        var out = ""
        for (i, t) in p.terms.enumerated() {
            let body = term(coef: t.coef.abs, pow: t.pow)
            if i == 0 {
                out += (t.coef.isNegative ? "-" : "") + body
            } else {
                out += (t.coef.isNegative ? "-" : "+") + body
            }
        }
        return out
    }
}

// MARK: - 逐项比对

public enum Compare {

    /// 学生对 / 正确 → 错误列表（空 = 全对）
    public static func run(student: StudentLine, correct: Poly) -> [Defect] {
        if student.poly == correct { return [] }

        var defects: [Defect] = []
        let sPows = Set(student.poly.terms.map { $0.pow })
        let cPows = Set(correct.terms.map { $0.pow })

        // 1) 同一次幂、系数不同
        for c in correct.terms where sPows.contains(c.pow) {
            let s = student.poly.coef(of: c.pow)
            if s == c.coef { continue }
            let st = student.terms.first { $0.pow == c.pow }
            let kind: DefectKind = (s == -c.coef) ? .wrongSign : .wrongCoefficient
            defects.append(Defect(kind: kind,
                                  wrongLatex: st?.text ?? LatexRender.term(coef: s, pow: c.pow),
                                  expectedLatex: LatexRender.term(coef: c.coef, pow: c.pow),
                                  span: st?.span,
                                  pow: c.pow,
                                  expectedPow: c.pow))
        }

        // 2) 多出来的项 / 少掉的项：按"最像"配对
        let extras = student.poly.terms.filter { !cPows.contains($0.pow) }
        let missings = correct.terms.filter { !sPows.contains($0.pow) }

        var usedExtra = Set<Int>()
        var usedMissing = Set<Int>()

        if !extras.isEmpty && !missings.isEmpty {
            var pairs: [(score: Int, ei: Int, mi: Int)] = []
            for (ei, e) in extras.enumerated() {
                for (mi, m) in missings.enumerated() {
                    // 幂次越接近越像同一个位置写错；同系数也加分
                    var score = 100 - Swift.abs(e.pow - m.pow) * 10
                    if e.coef.abs == m.coef.abs { score += 15 }
                    pairs.append((score, ei, mi))
                }
            }
            pairs.sort { $0.score > $1.score }
            for p in pairs where p.score > 0 {
                if usedExtra.contains(p.ei) || usedMissing.contains(p.mi) { continue }
                usedExtra.insert(p.ei)
                usedMissing.insert(p.mi)
                let e = extras[p.ei]
                let m = missings[p.mi]
                let st = student.terms.first { $0.pow == e.pow }
                defects.append(Defect(kind: .wrongTerm,
                                      wrongLatex: st?.text ?? LatexRender.term(coef: e.coef, pow: e.pow),
                                      expectedLatex: LatexRender.term(coef: m.coef, pow: m.pow),
                                      span: st?.span,
                                      pow: e.pow,
                                      expectedPow: m.pow))
            }
        }

        for (i, e) in extras.enumerated() where !usedExtra.contains(i) {
            let st = student.terms.first { $0.pow == e.pow }
            defects.append(Defect(kind: .extraTerm,
                                  wrongLatex: st?.text ?? LatexRender.term(coef: e.coef, pow: e.pow),
                                  span: st?.span,
                                  pow: e.pow))
        }
        for (i, m) in missings.enumerated() where !usedMissing.contains(i) {
            defects.append(Defect(kind: .missingTerm,
                                  expectedLatex: LatexRender.term(coef: m.coef, pow: m.pow),
                                  pow: m.pow,
                                  expectedPow: m.pow))
        }

        defects.sort { lhs, rhs in
            (lhs.span?.lowerBound ?? Int.max) < (rhs.span?.lowerBound ?? Int.max)
        }
        return defects
    }
}

// MARK: - 求导批改

public enum DerivativeCheck {

    public static func run(functionLatex: String, lineLatex: String) throws -> [Defect] {
        let f = try residual(functionLatex)
        let correct = f.derivative()
        guard correct.isValid else { throw MathError.unsupported("原函数系数太大") }
        let student: StudentLine
        do {
            student = try StudentLine.parse(lineLatex)
        } catch {
            return [Defect(kind: .parseError, wrongLatex: String(lineLatex.prefix(80)),
                           explanation: Explain.parseError)]
        }
        if student.poly == correct { return [] }
        if student.poly == f {
            // expected_latex 留空（圈整行，没有单独的"正确项"）；完整导数写在说明里
            return [Defect(kind: .notDerivative,
                           wrongLatex: student.body.trimmingCharacters(in: .whitespaces),
                           explanation: Explain.notDerivative(correct: correct))]
        }
        return Compare.run(student: student, correct: correct).map { d in
            var d = d
            d.explanation = Explain.derivative(d, function: f)
            return d
        }
    }

    /// CheckGate（PDF D1）要的「预期项数」：正确导数有几项
    public static func expectedTermCount(functionLatex: String) -> Int? {
        guard let f = try? residual(functionLatex) else { return nil }
        return f.derivative().terms.count
    }

    /// 等式 → 残差（lhs - rhs）；带标签 → 右侧；不做等式检查
    public static func residual(_ latex: String) throws -> Poly {
        let shape = LineShape.split(latex)
        switch shape {
        case .labelled(_, let body):
            return try PolyParser.parse(body)
        case .expression(let s):
            return try PolyParser.parse(s)
        case .equation(let lhs, let rhs):
            let r = try PolyParser.parse(lhs) - PolyParser.parse(rhs)
            guard r.isValid else { throw MathError.unsupported("数字太大，超出演示范围") }
            return r
        }
    }
}

// MARK: - 函数场景

public struct FunctionParam: Equatable {
    public var name: String
    public var value: Double     // 恒为正，符号在 sign 里（学生纸上写 3，滑条上就是 3）
    public var sign: Int
    public var min: Double
    public var max: Double
    public var pow: Int
    /// 滑条步长：整数系数 1，分数系数 0.5，其余 0.1
    public var step: Double = 1

    /// 这一项现在的带符号系数
    public var signedValue: Double { Double(sign) * value }
}

public struct Mark: Equatable {
    public var type: String      // extremum / tangent / zero
    public var kind: String?     // max / min / stationary
    public var x: Double
    public var y: Double
    public var slope: Double?
}

/// 绘图视窗，和契约里的 `view` 一致。默认 [-6,6]×[-10,10]
public struct ViewWindow: Equatable {
    public var xMin: Double
    public var xMax: Double
    public var yMin: Double
    public var yMax: Double
    public init(xMin: Double = -6, xMax: Double = 6, yMin: Double = -10, yMax: Double = 10) {
        self.xMin = xMin
        self.xMax = xMax
        self.yMin = yMin
        self.yMax = yMax
    }
    public static let standard = ViewWindow()
}

public struct FunctionScene: Equatable {
    public var terms: [Term]
    public var params: [FunctionParam]
    public var marks: [Mark]
    public var view: ViewWindow = .standard
    /// 降级码，例如 `marks_truncated`。前端在角落显示一行小字，不要静默
    public var degraded: [String] = []

    public var poly: Poly { Poly(terms) }

    /// 某一项绑定的是哪个滑条（契约里的 `terms[i].param`）。按幂次绑定，不靠下标
    public func paramName(forPow pow: Int) -> String? {
        params.first { $0.pow == pow }?.name
    }

    /// **P2 拖滑条时在 App 里直接调**：按新的滑条值重算多项式与极值点，滑条范围保持不变。
    /// `values` 的键是滑条名（a、b…），值是滑条上显示的数（恒正语义，符号仍由 `sign` 决定）。
    /// 例：`x^3-3x` 把 b 拖到 1 → `x^3-x`，极值点变成 ±0.577。a 拖到 0 → 直线，不标极值。
    public func updated(values: [String: Double]) -> FunctionScene {
        var newParams = params
        var newTerms: [Term] = []
        for (i, p) in params.enumerated() {
            let v = values[p.name] ?? p.value
            newParams[i].value = v
            let c = Rational.fromDouble(Double(p.sign) * v)
            if c.isValid { newTerms.append(Term(c, p.pow)) }
        }
        let poly = Poly(newTerms)
        let (m, deg) = FunctionSceneBuilder.marks(of: poly, view: view)
        return FunctionScene(terms: poly.terms, params: newParams, marks: m, view: view, degraded: deg)
    }

    /// 曲线上任意一点的切线（PDF 待定建议 A9：可拖的切点）。
    /// `derivative` 传学生自己写对的导数时，斜率就用学生的式子算 —— 手写、计算、图像连成一条线。
    public func tangent(at x: Double, derivative: Poly? = nil) -> Mark {
        let p = poly
        let d = derivative ?? p.derivative()
        return Mark(type: "tangent", kind: nil, x: x, y: p(x), slope: d(x))
    }

    /// 均匀采样，P2 画曲线用。超出 y 视窗的点照样返回，裁剪交给 Canvas
    public func samples(count: Int = 241) -> [(x: Double, y: Double)] {
        let n = Swift.max(count, 2)
        let p = poly
        let h = (view.xMax - view.xMin) / Double(n - 1)
        return (0..<n).map { i in
            let x = view.xMin + h * Double(i)
            return (x, p(x))
        }
    }
}

public enum FunctionSceneBuilder {

    static let names = ["a", "b", "c", "d", "k", "m", "n", "p", "q", "r", "s", "t", "u", "v", "w"]
    /// 极值点最多标几个（和 Python 参考实现一致）
    public static let maxMarks = 8

    public static func build(_ latex: String, view: ViewWindow = .standard) throws -> FunctionScene {
        let poly = try DerivativeCheck.residual(latex)
        guard !poly.isZero else { throw MathError.unsupported("函数是 0，没有可画的曲线") }
        var params: [FunctionParam] = []
        for (i, t) in poly.terms.enumerated() {
            let v = t.coef.abs.doubleValue
            let span = Swift.max(v * 2.0, 3.0)
            let step: Double = t.coef.d == 1 ? 1 : (t.coef.d == 2 ? 0.5 : 0.1)
            params.append(FunctionParam(name: names[Swift.min(i, names.count - 1)],
                                        value: v,
                                        sign: t.coef.isNegative ? -1 : 1,
                                        min: -span,
                                        max: span,
                                        pow: t.pow,
                                        step: step))
        }
        let (m, deg) = marks(of: poly, view: view)
        return FunctionScene(terms: poly.terms, params: params, marks: m, view: view, degraded: deg)
    }

    /// 兼容旧调用
    public static func marks(of poly: Poly) -> [Mark] { marks(of: poly, view: .standard).marks }

    /// 极值点 + 极值处的水平切线（幕二改对之后才画切线，由前端决定显示时机）。
    /// 只在视窗 x 范围内找。导数三次以上走数值求根，不再静默返回空。
    public static func marks(of poly: Poly, view: ViewWindow) -> (marks: [Mark], degraded: [String]) {
        guard poly.isValid, poly.degree >= 2 else { return ([], []) }
        let d1 = poly.derivative()
        var roots = realRoots(of: d1, in: view.xMin, view.xMax)
        var degraded: [String] = []
        if roots.count > maxMarks {
            roots = Array(roots.prefix(maxMarks))
            degraded.append("marks_truncated")
        }
        var out: [Mark] = []
        for r in roots {
            let x = clean(r)
            let y = clean(poly(r))
            let kind = extremumKind(d1, at: r)
            out.append(Mark(type: "extremum", kind: kind, x: x, y: y, slope: nil))
            if kind != "stationary" {
                out.append(Mark(type: "tangent", kind: nil, x: x, y: y, slope: 0))
            }
        }
        return (out, degraded)
    }

    /// 看导数在根两侧的符号：- → + 是极小，+ → - 是极大，不变号是驻点（如 x^3 在 0）。
    /// 比看二阶导稳：x^4 在 0 处二阶导也是 0，但它是极小。
    static func extremumKind(_ d1: Poly, at r: Double) -> String {
        let delta = 1e-4 * Swift.max(1.0, Swift.abs(r))
        let left = d1(r - delta)
        let right = d1(r + delta)
        if left < 0 && right > 0 { return "min" }
        if left > 0 && right < 0 { return "max" }
        return "stationary"
    }

    /// 保留 6 位小数，并把 -0 变成 0（否则 JSON 里会出现 "-0"）
    static func clean(_ v: Double) -> Double {
        let r = (v * 1e6).rounded() / 1e6
        return Swift.abs(r) < 5e-7 ? 0 : r
    }

    /// 实根。一、二次用公式（精确）；三次以上在 [lo, hi] 上数值求根。
    public static func realRoots(of p: Poly, in lo: Double = -6, _ hi: Double = 6) -> [Double] {
        guard p.isValid, !p.isZero, p.degree >= 1 else { return [] }
        let roots = p.degree <= 2 ? quadraticRoots(p) : numericRoots(p, lo, hi)
        return roots.filter { $0 >= lo - 1e-9 && $0 <= hi + 1e-9 }
    }

    static func quadraticRoots(_ p: Poly) -> [Double] {
        let a = p.coef(of: 2)
        let b = p.coef(of: 1)
        let c = p.coef(of: 0)
        if a.isZero {
            if b.isZero { return [] }
            return [-c.doubleValue / b.doubleValue]
        }
        let A = a.doubleValue
        let B = b.doubleValue
        let C = c.doubleValue
        let disc = B * B - 4 * A * C
        if disc < 0 { return [] }
        if disc == 0 { return [-B / (2 * A)] }
        let s = disc.squareRoot()
        let r1 = (-B - s) / (2 * A)
        let r2 = (-B + s) / (2 * A)
        return [Swift.min(r1, r2), Swift.max(r1, r2)]
    }

    /// 变号区间二分 + 偶重根（不变号的根 = 导数的根里函数值≈0 的那些）
    static func numericRoots(_ p: Poly, _ lo: Double, _ hi: Double) -> [Double] {
        var found: [Double] = []
        let n = 1200
        let h = (hi - lo) / Double(n)
        var x0 = lo
        var y0 = p(x0)
        if y0 == 0 { found.append(x0) }
        for i in 1...n {
            let x1 = lo + h * Double(i)
            let y1 = p(x1)
            if y1 == 0 {
                found.append(x1)
            } else if y0 != 0 && (y0 < 0) != (y1 < 0) {
                found.append(bisect(p, x0, x1))
            }
            x0 = x1
            y0 = y1
        }
        let scale = Swift.max(1.0, p.terms.map { Swift.abs($0.coef.doubleValue) }.max() ?? 1)
        for r in realRoots(of: p.derivative(), in: lo, hi) where Swift.abs(p(r)) < 1e-9 * scale {
            found.append(r)
        }
        found.sort()
        var out: [Double] = []
        for r in found {
            if let last = out.last, Swift.abs(r - last) < 1e-5 { continue }
            out.append(r)
        }
        return out
    }

    static func bisect(_ p: Poly, _ a0: Double, _ b0: Double) -> Double {
        var a = a0
        var b = b0
        var fa = p(a)
        for _ in 0..<80 {
            let m = (a + b) / 2
            let fm = p(m)
            if fm == 0 { return m }
            if (fa < 0) != (fm < 0) { b = m } else { a = m; fa = fm }
        }
        return (a + b) / 2
    }

    /// 函数模式的 CheckGate：能解析且不是 0 才刷新图像
    public static func isPlottable(_ latex: String) -> Bool {
        guard let p = try? DerivativeCheck.residual(latex) else { return false }
        return !p.isZero
    }
}

// MARK: - 矩阵（只做 2×2 / 3×3 乘法）

public enum MatrixCheck {

    public static func run(_ latex: String) throws -> [Defect] {
        let blocks = matrixBodies(latex)
        guard blocks.count >= 3 else {
            return [Defect(kind: .parseError, wrongLatex: String(latex.prefix(80)),
                           explanation: Explain.parseError)]
        }
        let a = try matrix(blocks[0])
        let b = try matrix(blocks[1])
        let expected = try matrix(blocks[2])
        // 先确认三个都是规整的矩形、尺寸能乘，再下标访问（旧版这里遇到空矩阵或参差行会越界闪退）
        guard let (ar, ac) = shape(a), let (br, bc) = shape(b), let (er, ec) = shape(expected),
              ac == br, er == ar, ec == bc else {
            return [Defect(kind: .wrongElement, wrongLatex: "尺寸不对",
                           explanation: "左边是几行几列、右边是几行几列？结果的尺寸应当是「左行数 × 右列数」。")]
        }
        var defects: [Defect] = []
        for i in 0..<ar {
            for j in 0..<bc {
                var sum = Rational.zero
                var pieces: [String] = []
                for k in 0..<br {
                    sum = sum + a[i][k] * b[k][j]
                    pieces.append("\(PlainRender.number(a[i][k]))×\(PlainRender.number(b[k][j]))")
                }
                if sum == expected[i][j] { continue }
                defects.append(Defect(kind: .wrongElement,
                                      wrongLatex: "\(expected[i][j])",
                                      expectedLatex: "\(sum)",
                                      row: i + 1, col: j + 1,
                                      explanation: "第 \(i + 1) 行乘第 \(j + 1) 列：\(pieces.joined(separator: " + ")) = \(PlainRender.number(sum))。"))
            }
        }
        return defects
    }

    /// 规整矩形才返回 (行, 列)
    static func shape(_ m: [[Rational]]) -> (Int, Int)? {
        guard let first = m.first, !first.isEmpty else { return nil }
        guard m.allSatisfy({ $0.count == first.count }) else { return nil }
        return (m.count, first.count)
    }

    /// \begin{pmatrix} … \end{pmatrix} 的内容。识别器也可能吐 bmatrix / matrix，一并认
    static func matrixBodies(_ s: String) -> [String] {
        for env in ["pmatrix", "bmatrix", "Bmatrix", "vmatrix", "matrix"] {
            let found = bodies(s, env)
            if found.count >= 3 { return found }
        }
        return bodies(s, "pmatrix")
    }

    static func bodies(_ s: String, _ env: String) -> [String] {
        var out: [String] = []
        var searchStart = s.startIndex
        let open = "\\begin{\(env)}"
        let close = "\\end{\(env)}"
        while let r = s.range(of: open, range: searchStart..<s.endIndex) {
            guard let end = s.range(of: close, range: r.upperBound..<s.endIndex) else { break }
            out.append(String(s[r.upperBound..<end.lowerBound]))
            searchStart = end.upperBound
        }
        return out
    }

    static func matrix(_ body: String) throws -> [[Rational]] {
        var rows: [[Rational]] = []
        for rowText in body.components(separatedBy: "\\\\") {
            let trimmed = rowText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            var cells: [Rational] = []
            for cell in trimmed.components(separatedBy: "&") {
                let poly = try PolyParser.parse(cell)
                guard poly.isConstant else {
                    throw MathError.unsupported("矩阵元素必须是常数")
                }
                cells.append(poly.terms.first?.coef ?? .zero)
            }
            rows.append(cells)
        }
        return rows
    }
}

// MARK: - 积分

public enum IntegralCheck {

    public struct Parsed {
        public var integrand: Poly
        public var lower: Rational?
        public var upper: Rational?
        public var answer: Poly
        public var hasConstant: Bool   // 学生写了 +C
        /// 学生原文答案（已去空白），wrong_latex 用它，圈的就是学生写的那一段
        public var answerText: String
    }

    public static func run(_ latex: String) throws -> [Defect] {
        let p = try parse(latex)
        let F = p.integrand.antiderivative()
        if let lo = p.lower, let hi = p.upper {
            // 多项式的定积分用牛顿-莱布尼茨精确算（有理数），不再用 Simpson 近似
            let exact = F.evaluate(hi) - F.evaluate(lo)
            let student = p.answer(0.0)
            if p.answer.isConstant, exact.isValid, Swift.abs(student - exact.doubleValue) < 1e-6 { return [] }
            let shown = exact.isValid ? LatexRender.term(coef: exact, pow: 0) : String(format: "%.6g", simpson(p.integrand, lo.doubleValue, hi.doubleValue))
            return [Defect(kind: .wrongCoefficient,
                           wrongLatex: p.answerText,
                           expectedLatex: shown,
                           explanation: "原函数是 \(PlainRender.poly(F))，代入上下限相减：结果是 \(PlainRender.number(exact))。")]
        }
        // 不定积分：对学生结果求导，看是否回到被积函数
        if p.answer.derivative() == p.integrand { return [] }
        let back = p.answer.derivative()
        // 只差一个常数倍（漏写 / 多写系数）单独报 wrong_coefficient，和 Python 参考实现一致
        if let c = scale(p.answer, F), c != .one {
            return [Defect(kind: .wrongCoefficient,
                           wrongLatex: p.answerText,
                           expectedLatex: LatexRender.poly(F) + (p.hasConstant ? "+C" : ""),
                           explanation: "把 \(PlainRender.poly(p.answer)) 求导得 \(PlainRender.poly(back))，比 \(PlainRender.poly(p.integrand)) 多乘了 \(PlainRender.number(c))；原函数应是 \(PlainRender.poly(F)) + C。")]
        }
        return [Defect(kind: .integrandMismatch,
                       wrongLatex: p.answerText,
                       expectedLatex: LatexRender.poly(F) + "+C",
                       explanation: "把 \(PlainRender.poly(p.answer)) 求导得 \(PlainRender.poly(back))，回不到 \(PlainRender.poly(p.integrand))；原函数应是 \(PlainRender.poly(F)) + C。")]
    }

    public static func parse(_ raw: String) throws -> Parsed {
        // 先做和普通行一样的清洗（\, \mathrm{d}x \frac 全角减号），积分号本身保留
        let latex = LatexText.expandFrac(LatexText.stripMacros(LatexText.fixUnicode(raw)))
        let chars = Array(latex)
        guard let intIndex = indexOf(chars, "\\int") else {
            throw MathError.unsupported("没找到积分号")
        }
        var i = intIndex + 4
        var lower: Rational? = nil
        var upper: Rational? = nil
        // 下限 _{...} 或 _
        if i < chars.count, chars[i] == "_" {
            i += 1
            lower = try readGroup(chars, &i)
        }
        if i < chars.count, chars[i] == "^" {
            i += 1
            upper = try readGroup(chars, &i)
        }
        // 找到 "d x"
        var dIndex: Int? = nil
        var j = i
        while j + 1 < chars.count {
            if chars[j] == "d", chars[j + 1].isLetter {
                dIndex = j
                break
            }
            j += 1
        }
        guard let dj = dIndex else { throw MathError.unsupported("积分里没找到 dx") }
        let integrandText = LatexText.normalizeCaret(String(chars[i..<dj]))
        let integrand = try PolyParser.parse(integrandText)
        // = 之后是学生答案
        var eqIndex: Int? = nil
        var k = dj + 2
        while k < chars.count {
            if chars[k] == "=" { eqIndex = k; break }
            k += 1
        }
        guard let eq = eqIndex else { throw MathError.unsupported("积分这一行没有等号") }
        var answerText = LatexText.normalizeCaret(String(chars[(eq + 1)..<chars.count]))
        var hasConstant = false
        // 末尾的 +C / + c 视为积分常数（先去空格，免得 "x^2 + C" 漏掉）
        let compact = String(answerText.filter { !$0.isWhitespace })
        if compact.count >= 2 {
            let tail = Array(compact)
            let last = tail[tail.count - 1]
            let before = tail[tail.count - 2]
            if last.isLetter, last != "x", before == "+" {
                hasConstant = true
                answerText = String(tail[0..<(tail.count - 2)])
            }
        }
        answerText = String(answerText.filter { !$0.isWhitespace })
        let answer = try PolyParser.parse(answerText)
        return Parsed(integrand: integrand, lower: lower, upper: upper, answer: answer,
                      hasConstant: hasConstant, answerText: answerText)
    }

    /// 两个多项式相差一个常数倍时返回倍数（用于「漏乘了系数」）
    static func scale(_ a: Poly, _ b: Poly) -> Rational? {
        guard let ta = a.terms.first, let tb = b.terms.first, ta.pow == tb.pow, !tb.coef.isZero else { return nil }
        let k = ta.coef / tb.coef
        guard k.isValid, !k.isZero else { return nil }
        return Poly(b.terms.map { Term($0.coef * k, $0.pow) }) == a ? k : nil
    }

    static func indexOf(_ chars: [Character], _ needle: String) -> Int? {
        let n = Array(needle)
        if n.isEmpty || chars.count < n.count { return nil }
        for i in 0...(chars.count - n.count) {
            var ok = true
            for k in 0..<n.count where chars[i + k] != n[k] { ok = false; break }
            if ok { return i }
        }
        return nil
    }

    static func readGroup(_ chars: [Character], _ i: inout Int) throws -> Rational {
        if i < chars.count, chars[i] == "{" {
            var depth = 0
            let start = i
            while i < chars.count {
                if chars[i] == "{" { depth += 1 }
                if chars[i] == "}" {
                    depth -= 1
                    if depth == 0 { break }
                }
                i += 1
            }
            let text = String(chars[(start + 1)..<i])
            i += 1
            let p = try PolyParser.parse(text)
            return p.terms.first?.coef ?? .zero
        }
        // _0 这种单个字符
        if i < chars.count {
            let text = String(chars[i])
            i += 1
            return Rational(Int(text) ?? 0)
        }
        throw MathError.unexpectedEnd
    }

    /// 多项式在 [a,b] 上的 Simpson 积分；三次以下精确
    public static func simpson(_ p: Poly, _ a: Double, _ b: Double, _ n: Int = 200) -> Double {
        let steps = n % 2 == 0 ? n : n + 1
        let h = (b - a) / Double(steps)
        var acc = p(a) + p(b)
        for i in 1..<steps {
            let x = a + h * Double(i)
            acc += (i % 2 == 0 ? 2.0 : 4.0) * p(x)
        }
        return acc * h / 3.0
    }
}

// MARK: - 推导等价

public enum StepCheck {

    public static func run(_ lines: [String]) throws -> [Defect] {
        var prev: Poly? = nil
        var defects: [Defect] = []
        for (i, latex) in lines.enumerated() {
            let cur: Poly
            do {
                cur = try DerivativeCheck.residual(latex)
            } catch {
                defects.append(Defect(kind: .parseError, wrongLatex: String(latex.prefix(80)),
                                      row: i + 1, explanation: Explain.parseError))
                prev = nil
                continue
            }
            if let p = prev, !proportional(p, cur) {
                defects.append(Defect(kind: .notEquivalent,
                                      wrongLatex: latex.trimmingCharacters(in: .whitespaces),
                                      row: i + 1,
                                      explanation: "第 \(i + 1) 行和上一行不等价：两边做的变形要一样，检查移项或两边同除这一步。"))
            }
            prev = cur
        }
        return defects
    }

    /// 两个残差相差一个非零常数倍就算等价（`2x=4` → `x=2` 是两边同除 2，旧版会误判为不等价）
    public static func proportional(_ a: Poly, _ b: Poly) -> Bool {
        if a == b { return true }
        guard let ta = a.terms.first, let tb = b.terms.first, ta.pow == tb.pow, !tb.coef.isZero else {
            return a.isZero && b.isZero
        }
        let k = ta.coef / tb.coef
        guard k.isValid, !k.isZero else { return false }
        return Poly(b.terms.map { Term($0.coef * k, $0.pow) }) == a
    }
}

// MARK: - 几何（只做"自由点 / 依赖点"的对象模型，不做约束求解）

public struct GeoPoint: Equatable {
    public var id: String
    public var x: Double
    public var y: Double
    public var free: Bool
}

public struct GeoRelation: Equatable {
    public var type: String        // midpoint
    public var of: [String]
    public var point: String
}

public enum Geometry {

    /// 拖动自由点后重算依赖点。演示只有 midpoint 一种关系。
    public static func resolve(points: [GeoPoint], relations: [GeoRelation]) -> [GeoPoint] {
        var byId: [String: GeoPoint] = [:]
        for p in points { byId[p.id] = p }
        var result = points
        for _ in 0..<relations.count {
            for r in relations where r.type == "midpoint" {
                guard r.of.count == 2,
                      let a = byId[r.of[0]], let b = byId[r.of[1]] else { continue }
                let mid = GeoPoint(id: r.point, x: (a.x + b.x) / 2, y: (a.y + b.y) / 2, free: false)
                byId[r.point] = mid
                if let idx = result.firstIndex(where: { $0.id == r.point }) {
                    result[idx] = mid
                } else {
                    result.append(mid)
                }
            }
        }
        return result
    }

    /// 重心。三条中线交于一点不需要求解器：每条中线都是「顶点→对边中点」，
    /// 而三个中点由 midpoint 关系算出，交点自然落在这里。
    public static func centroid(_ a: GeoPoint, _ b: GeoPoint, _ c: GeoPoint) -> (x: Double, y: Double) {
        ((a.x + b.x + c.x) / 3.0, (a.y + b.y + c.y) / 3.0)
    }
}

// MARK: - 提示守门员（P4 对 P3 的约定）

/// 模型生成的问句必须过这三关：不太长、不含"答案是"这类句式、不含正确项的记号。
/// 任何一关不过，就换成 `Defect.fallbackHint()`。答辩必问这一条。
public enum HintGuard {

    public static let maxLength = 40

    static let answerPhrases = ["答案是", "正确答案", "应该写成", "应该是", "结果为", "得数是"]

    /// 抹掉 LaTeX 噪音，让 `x^{2}` 和 `x^2` 变成同一个东西
    public static func normalize(_ text: String?) -> String {
        guard let text = text else { return "" }
        var out = ""
        for ch in text {
            switch ch {
            case " ", "\t", "\n", "\\", "{", "}", "(", ")", "*", "_", "$", "`", "^", "'":
                continue
            default:
                out.append(ch)
            }
        }
        return out
    }

    /// 返回问题列表，空 = 这句可以发出去
    public static func problems(_ hint: String?,
                                expected: String? = nil,
                                wrong: String? = nil,
                                full: String? = nil) -> [String] {
        guard let hint = hint, !hint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ["empty"]
        }
        var out: [String] = []

        if hint.count > maxLength {
            out.append("too_long:\(hint.count)")
        }
        for phrase in answerPhrases where hint.contains(phrase) {
            out.append("phrase:\(phrase)")
        }

        // 先抹掉学生自己写的那一项（它包含正确答案的子串，否则永远误报）
        var scrubbed = hint
        if let w = wrong {
            scrubbed = scrubbed.replacingOccurrences(of: w, with: "")
            scrubbed = scrubbed.replacingOccurrences(of: normalize(w), with: "")
        }
        let haystack = normalize(scrubbed)
        for (label, target) in [("expected", expected), ("full", full)] {
            let needle = normalize(target)
            if !needle.isEmpty && haystack.contains(needle) {
                out.append("leak:\(label):\(target ?? "")")
            }
        }
        return out
    }

    /// 能用就返回模型那句，不能用就返回兜底
    public static func safe(_ hint: String?,
                            fallback: String,
                            expected: String? = nil,
                            wrong: String? = nil,
                            full: String? = nil) -> (text: String, rejectedBecause: [String]) {
        let issues = problems(hint, expected: expected, wrong: wrong, full: full)
        if issues.isEmpty, let hint = hint {
            return (hint.trimmingCharacters(in: .whitespacesAndNewlines), [])
        }
        return (fallback, issues)
    }
}
