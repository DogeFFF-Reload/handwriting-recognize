#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation
import MathEngine

/// 「检查我这一步」：学生自己写的 f'(x) = …（或 f'(2) = …、f''(x) = …），和纸上写过的 f(x) = … 对一下。
/// 只圈出有问题的地方，不直接给答案；提示分三级（一句反问 → 相关的规则 → 该是什么），学生自己点开。
/// 多项式的一阶导数用 P4 的 MathEngine 逐项比对，圈得到具体那一项；不是多项式（sin x、e^x……）、在一点取值、
/// 高阶导数，或者这一行逐项读不出来，就在一串点上比数值（P4 的 DerivativeComparison），只判整行。
/// 提示按错误码、按原函数用到的求导法则套模板，不调模型、没有延迟。
public enum StepReview {
    /// 一处问题。
    public struct Issue: Equatable {
        /// MathEngine 的错误码：wrong_term、wrong_coefficient、wrong_sign、missing_term、extra_term、not_derivative；
        /// 整行判的是 whole_line。
        public var kind: String
        /// 学生写的那一项（普通文字，如「−3x」）；漏项、整行时为空。
        public var written: String
        /// 圈在哪里（画布坐标）。漏项时是这一行末尾的一小块，整行时是等号右边。
        public var box: CGRect
        /// 三级提示：一句反问、相关的规则、该是什么。
        public var hints: [String]
        /// 最后一级里要排成式子的正确结果（整行判时：f'(x) = \sin x + x\cos x）；逐项判时为 nil，答案写在提示里。
        public var answerLatex: String?
    }

    public struct Result: Equatable {
        /// 这一步全对。
        public var ok: Bool
        public var issues: [Issue]
        /// 正确的结果（LaTeX，带左边）：f'(x)=3x^{2} - 3、f'(2)=9。
        public var answer: String
        /// 逐项比对的（多项式），不是整行比数值的。
        public var byTerm: Bool
    }

    public enum Problem: Error, Equatable {
        /// 不是「f'(x) = …」，或者等号后面还没写。
        case notADerivative
        /// 等号后面读不出来（有看不懂的字、多了别的字母）。
        case unreadable
    }

    /// `line`：这一行的笔画（圈错项用）；`function`：上面那条 f(x) = …（参数取滑条上现在的值）；`stepLatex`：识别出的这一行。
    public static func review(line: InkLine, function d: FunctionDefinition, stepLatex: String) throws -> Result {
        guard let request = DerivativeRequest.parse(stepLatex), let rhs = DerivativeComparison.rightHandSide(stepLatex) else {
            throw Problem.notADerivative
        }
        var expected = d.body
        for _ in 0..<request.order { expected = expected.derivative(d.variable) }
        let lhs = request.lhsLatex(variable: d.variable)
        // 多项式的一阶导数：逐项比对，圈到具体那一项（逐项读不出来就往下走，整行比）
        if request.order == 1, request.point == nil, d.variable == "x", let poly = d.polynomial,
           let r = byTerm(line: line, functionLatex: MathEngineGrading.polynomialLatex(poly), stepLatex: stepLatex,
                          answer: lhs + "=" + expected.latex) {
            return r
        }
        if let p = request.point { expected = expected.substituting(d.variable, with: .number(p)) }
        guard let same = DerivativeComparison.matches(student: rhs, expected: expected, variable: d.variable) else {
            throw Problem.unreadable
        }
        let answer = lhs + "=" + (request.point == nil ? expected.latex : MathExpr.formatNumber(expected.evaluate([:])))
        guard !same else { return Result(ok: true, issues: [], answer: answer, byTerm: false) }
        let issue = Issue(kind: "whole_line", written: "", box: rightSide(of: line),
                          hints: wholeLineHints(request, function: d, lhs: lhs), answerLatex: answer)
        return Result(ok: false, issues: [issue], answer: answer, byTerm: false)
    }

    /// 逐项比对（MathEngine）。这一行逐项读不出来时返回 nil：交给整行比数值。
    static func byTerm(line: InkLine, functionLatex: String, stepLatex: String, answer: String) -> Result? {
        guard let f = try? MathEngine.DerivativeCheck.residual(functionLatex),
              let defects = try? MathEngine.DerivativeCheck.run(functionLatex: functionLatex, lineLatex: stepLatex),
              !defects.contains(where: { $0.kind == .parseError }) else { return nil }
        guard !defects.isEmpty else { return Result(ok: true, issues: [], answer: answer, byTerm: true) }
        let student = try? StudentLine.parse(stepLatex)
        let boxes = TermSegmenter.termBoxes(strokes: line.strokes, expectedCount: student?.terms.count)
        let issues = defects.map { d -> Issue in
            let term = d.span.flatMap { span in student?.terms.first { $0.span == span } }
            let written = term.map { PlainRender.term($0.coef, $0.pow) } ?? ""
            return Issue(kind: d.kind.rawValue, written: written,
                         box: box(for: d, line: line, student: student, termBoxes: boxes),
                         hints: hints(for: d, function: f, written: written), answerLatex: nil)
        }
        return Result(ok: false, issues: issues, answer: answer, byTerm: true)
    }

    /// 整行判错时圈等号右边（切不出等号就圈整行）。
    static func rightSide(of line: InkLine) -> CGRect {
        guard let boxes = TermSegmenter.termBoxes(strokes: line.strokes), let first = boxes.first else {
            return line.band.insetBy(dx: -8, dy: -8)
        }
        return boxes.dropFirst().reduce(first) { $0.union($1) }.insetBy(dx: -8, dy: -8)
    }

    /// 整行判错的三级提示：先问一句，再提醒原函数用得上的求导法则，最后是正确结果（排成式子，见 answerLatex）。
    static func wholeLineHints(_ request: DerivativeRequest, function d: FunctionDefinition, lhs: String) -> [String] {
        let name = Explanation.pretty(lhs).replacingOccurrences(of: "'", with: "′")
        let first: String
        if let p = request.point {
            first = "\(name) 是导函数在 x = \(Numerics.plain(p)) 处的值：导函数先求对了吗？"
        } else if request.order > 1 {
            first = "\(name) 要连着求 \(request.order) 次导：每一次都求对了吗？"
        } else {
            first = "这一行和真正的导数对不上：每一项、每个因子都求导了吗？"
        }
        var rules = Array(rules(for: d.body, variable: d.variable).prefix(3))
        if request.point != nil { rules.insert("先求出导函数，再把 x 的值代进去", at: 0) }
        let second = rules.isEmpty ? "逐项求导：常数的导数是 0，xⁿ 的导数是 n·xⁿ⁻¹。" : rules.joined(separator: "；") + "。"
        return [first, second, "正确的是："]
    }

    /// 原函数里用得上的求导法则（从外往里）：乘积、商、链式法则，和 sin、eˣ、ln 这些基本导数。
    static func rules(for e: MathExpr, variable v: String) -> [String] {
        var out: [String] = []
        func add(_ s: String) { if !out.contains(s) { out.append(s) } }
        let chain = "链式法则：外层求导，再乘里层的导数"
        func walk(_ e: MathExpr) {
            switch e {
            case .multiply(let a, let b):
                if a.depends(on: v), b.depends(on: v) { add("乘积：(uv)′ = u′v + uv′") }
                walk(a)
                walk(b)
            case .divide(let a, let b):
                if b.depends(on: v) { add("商：(u/v)′ = (u′v − uv′)/v²") }
                walk(a)
                walk(b)
            case .power(let a, let b):
                if b.depends(on: v) {
                    add(a == MathExpr.e ? "(eᵘ)′ = eᵘ·u′" : "(aᵘ)′ = aᵘ·ln a·u′")
                } else if a.depends(on: v) {
                    add("(xⁿ)′ = n·xⁿ⁻¹")
                    if a != .symbol(v) { add(chain) }
                }
                walk(a)
                walk(b)
            case .call(let name, let args):
                if let u = args.last, u.depends(on: v) {
                    if let r = basics[name] { add(r) }
                    if u != .symbol(v) { add(chain) }
                }
                args.forEach(walk)
            case .negate(let a):
                walk(a)
            case .add(let a, let b), .subtract(let a, let b):
                walk(a)
                walk(b)
            default:
                break
            }
        }
        walk(e)
        return out
    }

    static let basics: [String: String] = [
        "sin": "(sin x)′ = cos x", "cos": "(cos x)′ = −sin x", "tan": "(tan x)′ = 1/cos²x",
        "ln": "(ln x)′ = 1/x", "lg": "(lg x)′ = 1/(x ln 10)", "log": "(logₐx)′ = 1/(x ln a)", "exp": "(eˣ)′ = eˣ",
        "sqrt": "(√x)′ = 1/(2√x)", "arcsin": "(arcsin x)′ = 1/√(1 − x²)", "arccos": "(arccos x)′ = −1/√(1 − x²)",
        "arctan": "(arctan x)′ = 1/(1 + x²)",
    ]

    // MARK: 圈哪里

    /// 先用笔画切出来的项（P3 的 TermSegmenter），切不出来按字符位置估算再吸附到笔画上；漏项圈在这一行末尾。
    static func box(for d: Defect, line: InkLine, student: StudentLine?, termBoxes: [CGRect]?) -> CGRect {
        let band = line.band
        if d.kind == .missingTerm {
            let w = max(34, band.height * 0.8)
            return CGRect(x: band.maxX + 6, y: band.minY, width: w, height: band.height)
        }
        if d.kind == .notDerivative, let boxes = termBoxes, let first = boxes.first {
            return boxes.dropFirst().reduce(first) { $0.union($1) }.insetBy(dx: -8, dy: -8)
        }
        guard let span = d.span, let student else { return band.insetBy(dx: -8, dy: -8) }
        if let i = student.termIndex(forCharSpan: span), let boxes = termBoxes, i < boxes.count {
            return boxes[i].insetBy(dx: -8, dy: -8)
        }
        let lineBox = Box(x: Double(band.minX), y: Double(band.minY), w: Double(band.width), h: Double(band.height))
        let estimate = TermBox.estimate(line: lineBox, label: student.label, body: student.body, span: span)
        let strokes = line.strokes.map { s in
            MathEngine.InkStroke(id: s.id, points: s.points.map { [Double($0.x), Double($0.y), 0, 0.5] })
        }
        let b = TermBox.snap(estimate, strokes: strokes) ?? estimate
        return CGRect(x: b.x, y: b.y, width: b.w, height: b.h)
    }

    // MARK: 三级提示

    /// 第一级只把注意力引到这一项上（反问），第二级提醒规则，第三级才说这一项该是什么。都不含「你错了」。
    static func hints(for d: Defect, function f: Poly, written: String) -> [String] {
        let mine = written.isEmpty ? "这一项" : written
        switch d.kind {
        case .wrongTerm:
            // 学生那一项的次数是 k；它本该是原式里 n 次那一项的导数（正确结果是 n − 1 次）
            let n = (d.expectedPow ?? 0) + 1
            let k = d.pow ?? n
            let orig = PlainRender.term(f.coef(of: n), n)
            let first: String
            if k == n {
                first = n == 1 ? "一次项求导后，还会带着 x 吗？" : "\(orig) 求导后，x 的指数还是 \(n) 吗？"
            } else {
                first = "\(mine) 是从原式哪一项求导来的？次数对得上吗？"
            }
            return [first, rule(n), "\(orig) 求导后是 \(derived(f, n))，这一项应该写 \(derived(f, n))。"]
        case .wrongCoefficient:
            let n = (d.pow ?? 0) + 1
            let orig = PlainRender.term(f.coef(of: n), n)
            return ["\(mine) 前面的系数再算一次：原来的指数去哪儿了？", rule(n),
                    "\(orig) 求导后是 \(derived(f, n))。"]
        case .wrongSign:
            let n = (d.pow ?? 0) + 1
            let orig = PlainRender.term(f.coef(of: n), n)
            let sign = f.coef(of: n).isNegative ? "负" : "正"
            return ["先只看符号：\(mine) 前面该是正号还是负号？",
                    "求导不改变系数的符号：原式里 \(orig) 前面是\(sign)号。",
                    "这一项应该是 \(derived(f, n))。"]
        case .missingTerm:
            let n = (d.pow ?? 0) + 1
            let orig = PlainRender.term(f.coef(of: n), n)
            return ["原函数的每一项都求导了吗？是不是少写了一项？",
                    "原式里的 \(orig) 求导后不是 0，也要写出来。",
                    "漏掉的是 \(derived(f, n))（由 \(orig) 求导得到）。"]
        case .extraTerm:
            let k = d.pow ?? 0
            let copied = !f.coef(of: k).isZero
            let second: String
            if k == 0, !f.coef(of: 0).isZero {
                second = "常数求导得 0。"
            } else if copied {
                second = "求导后每一项的次数都要降 1：xⁿ → n·xⁿ⁻¹。"
            } else {
                second = "原式里没有哪一项求导后会得到 \(mine)。"
            }
            return ["\(mine) 是从原式哪一项求导来的？", second, "\(mine) 这一项应当去掉。"]
        case .notDerivative:
            return ["右边和原函数一样——每一项都求导了吗？", "幂函数求导：xⁿ 的导数是 n·xⁿ⁻¹，常数的导数是 0。",
                    "导数应是 \(PlainRender.poly(f.derivative()))。"]
        default:
            return [d.fallbackHint()]
        }
    }

    /// 原式里 n 次那一项求导后的样子（普通文字）。
    static func derived(_ f: Poly, _ n: Int) -> String {
        PlainRender.term(f.coef(of: n) * Rational(n), max(n - 1, 0))
    }

    /// 「x 求导得 1」「x³ 求导得 3x²」，并说清楚指数到哪里去了。
    static func rule(_ n: Int) -> String {
        switch n {
        case 0: return "常数求导得 0。"
        case 1: return "x 求导得 1，所以 ax 求导后只剩系数 a。"
        default:
            let lower = n - 1 == 1 ? "x" : "x" + PlainRender.superscript(n - 1)
            return "x\(PlainRender.superscript(n)) 求导得 \(n)\(lower)：指数 \(n) 乘到系数上，指数再减 1。"
        }
    }
}
