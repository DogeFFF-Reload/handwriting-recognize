#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation
import MathEngine

/// 「检查我这一步」：学生自己写的 f'(x) = …，和纸上写过的 f(x) = … 对一下。
/// 只圈出有问题的那一项，不直接给答案；提示分三级（一句反问 → 相关的规则 → 这一项该是什么），学生自己点开。
/// 判对错用 P4 的 MathEngine（逐项比对），提示按错误码套模板，不调模型、没有延迟。首版只覆盖多项式的一阶导数。
public enum StepReview {
    /// 一处问题。
    public struct Issue: Equatable {
        /// MathEngine 的错误码：wrong_term、wrong_coefficient、wrong_sign、missing_term、extra_term、not_derivative。
        public var kind: String
        /// 学生写的那一项（普通文字，如「−3x」）；漏项时为空。
        public var written: String
        /// 圈在哪里（画布坐标）。漏项时是这一行末尾的一小块。
        public var box: CGRect
        /// 三级提示：一句反问、相关的规则、这一项该是什么。
        public var hints: [String]
    }

    public struct Result: Equatable {
        /// 这一步全对。
        public var ok: Bool
        public var issues: [Issue]
        /// 正确的导数（LaTeX，不带左边）。
        public var answer: String
    }

    public enum Problem: Error, Equatable {
        /// 不是「f'(x) = …」，或者等号后面还没写。
        case notADerivative
        /// 写的是 f''(x)：首版只检查一阶导数。
        case higherOrder
        /// 原函数不是多项式（三角、指数、带参数……）。
        case unsupportedFunction
        /// 这一行读不出来。
        case unreadable
    }

    /// `line`：这一行的笔画（圈错项用）；`functionLatex`：上面那条 f(x) = …；`stepLatex`：识别出的这一行。
    public static func review(line: InkLine, functionLatex: String, stepLatex: String) throws -> Result {
        guard let request = DerivativeRequest.parse(stepLatex) else { throw Problem.notADerivative }
        guard request.order == 1 else { throw Problem.higherOrder }
        guard let rhs = Solver.splitEquals(stepLatex).rhs, !rhs.isEmpty else { throw Problem.notADerivative }
        let f: Poly
        let defects: [Defect]
        do {
            f = try MathEngine.DerivativeCheck.residual(functionLatex)
            defects = try MathEngine.DerivativeCheck.run(functionLatex: functionLatex, lineLatex: stepLatex)
        } catch {
            throw Problem.unsupportedFunction
        }
        let answer = LatexRender.poly(f.derivative())
        if defects.contains(where: { $0.kind == .parseError }) { throw Problem.unreadable }
        guard !defects.isEmpty else { return Result(ok: true, issues: [], answer: answer) }

        let student = try? StudentLine.parse(stepLatex)
        let boxes = TermSegmenter.termBoxes(strokes: line.strokes, expectedCount: student?.terms.count)
        let issues = defects.map { d -> Issue in
            let term = d.span.flatMap { span in student?.terms.first { $0.span == span } }
            let written = term.map { PlainRender.term($0.coef, $0.pow) } ?? ""
            return Issue(kind: d.kind.rawValue, written: written,
                         box: box(for: d, line: line, student: student, termBoxes: boxes),
                         hints: hints(for: d, function: f, written: written))
        }
        return Result(ok: false, issues: issues, answer: answer)
    }

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
