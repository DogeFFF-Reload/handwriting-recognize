//
//  MathEngineGrading.swift
//  把 MathEngine（P4）的判分结果翻译成 InkCore 的 `Annotation`。判分逻辑一行都不在这里。
//  差异只有三处：bbox 的写法、说明是整行一条还是每个错误一条、错误码的名字。
//  App 批改求导行走这里；临时的 `DerivativeCheck` 保留到真机跑通再删（P3 删）。
//

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation
import MathEngine

/// 「批改」的结果。
public struct DerivativeGrade: Equatable {
    /// 给 App 画圈用的批注。socratic 模式下没有正确项和说明。
    public var annotation: Annotation
    /// socratic 模式下圈旁的一句反问；direct 模式为 nil（说明在 annotation.explanation）。
    public var question: String?
}

public enum MathEngineGrading {

    /// 门禁 D1 的「预期项数」：正确导数有几项。解析不出来返回 nil（门禁就不看项数）。
    public static func expectedTermCount(functionLatex: String) -> Int? {
        MathEngine.DerivativeCheck.expectedTermCount(functionLatex: functionLatex)
    }

    /// 一行 → 批注。`nil` 表示这一行压根没解析出来（调用方按 D1 提示「没看清」）。
    public static func annotation(line: InkLine,
                                  functionLatex: String,
                                  derivativeLatex: String,
                                  mode: FeedbackMode = .direct) -> Annotation? {
        let band = MathEngine.Box(x: Double(line.band.minX), y: Double(line.band.minY),
                                  w: Double(line.band.width), h: Double(line.band.height))
        let request = MathEngine.CheckRequest(
            mode: "derivative",
            lines: [.init(id: line.id, latex: derivativeLatex, bbox: band, revision: line.revision)],
            context: .init(functionLatex: functionLatex),
            strokes: line.strokes.map { s in
                MathEngine.InkStroke(id: s.id, points: s.points.map { [Double($0.x), Double($0.y), 0, 0.5] })
            },
            region: .init(x: Double(line.band.minX), y: Double(line.band.minY),
                          w: Double(line.band.width), h: Double(line.band.height), scale: 2),
            feedbackMode: mode == .direct ? .direct : .socratic
        )

        let result = MathEngineAPI.check(request)
        if result.errors.isEmpty {
            return Annotation(lineID: line.id, revision: line.revision, ok: true, feedbackMode: mode)
        }
        if result.errors.allSatisfy({ $0.kind == "parse_error" }) { return nil }

        let student = try? MathEngine.StudentLine.parse(derivativeLatex)
        let function = try? MathEngine.DerivativeCheck.residual(functionLatex)
        // 圈错项优先用 P3 的笔画切分（比按字符宽度估算准）；切不出来退回引擎给的框或整行。
        let termBoxes = TermSegmenter.termBoxes(strokes: line.strokes, expectedCount: student?.terms.count)

        var errors: [AnnotationError] = []
        var explanation: String?
        for e in result.errors where e.kind != "parse_error" {
            let index = e.charSpan.flatMap { s in
                s.count == 2 ? student?.termIndex(forCharSpan: s[0]..<s[1]) : nil
            }
            let mapped = classify(e, index: index, student: student, function: function)
            let box: CGRect
            if let i = index, let boxes = termBoxes, i < boxes.count {
                box = boxes[i]
            } else if let b = e.bbox {
                box = CGRect(x: b.x, y: b.y, width: b.w, height: b.h)
            } else {
                box = line.band
            }
            errors.append(AnnotationError(kind: mapped.kind,
                                          wrongLatex: e.wrongLatex ?? "",
                                          expectedLatex: mode == .direct ? mapped.expected : nil,
                                          bbox: BBox.array(box)))
            if explanation == nil { explanation = mapped.explanation ?? e.explanation }
        }
        if errors.isEmpty {
            errors = [AnnotationError(kind: "whole_line", wrongLatex: derivativeLatex,
                                      expectedLatex: nil, bbox: BBox.array(line.band))]
        }
        return Annotation(lineID: line.id, revision: line.revision, ok: false, feedbackMode: mode,
                          errors: errors, explanation: mode == .direct ? explanation : nil)
    }

    /// App 的「批改」用这个：批注 + socratic 模式下圈旁的一句反问。
    /// 先按 direct 判一遍（反问要拿正确项做泄题检查），socratic 再把正确项和说明抹掉。
    public static func grade(line: InkLine,
                             functionLatex: String,
                             derivativeLatex: String,
                             mode: FeedbackMode = .direct) -> DerivativeGrade? {
        guard let full = annotation(line: line, functionLatex: functionLatex,
                                    derivativeLatex: derivativeLatex, mode: .direct) else { return nil }
        guard mode == .socratic else { return DerivativeGrade(annotation: full, question: nil) }
        return DerivativeGrade(annotation: full.redactedForSocratic(),
                               question: full.errors.first.map(question))
    }

    /// 圈旁的一句反问（模板，不调模型）。带出了正确项就换成最保守的一句。
    static func question(_ e: AnnotationError) -> String {
        let w = Explanation.pretty(e.wrongLatex)
        let q: String
        switch e.kind {
        case "not_differentiated": q = "\(w) 这一项求导后还剩什么？"
        case "wrong_coef": q = "\(w) 的系数再算一次：指数乘到前面之后还剩多少？"
        case "wrong_sign": q = "先只看符号：\(w) 该是正还是负？"
        case "missing_term": q = "原函数里还有哪一项没有求导？"
        case "extra_term": q = "\(w) 是从原函数哪一项变过来的？"
        default: q = "\(w) 这一项单独再求一次导，会得到什么？"
        }
        let leaks = [e.expectedLatex, e.expectedLatex.map(Explanation.pretty)].contains { expected in
            !MathEngine.HintGuard.problems(q, expected: expected, wrong: w).isEmpty
        }
        return leaks ? "这一项求导后还剩什么？" : q
    }

    /// 次数 → 系数 写回 LaTeX（MathEngine 只吃纯数字系数的多项式）：[3: 1, 1: -3] → x^3-3x
    public static func polynomialLatex(_ p: [Int: Double]) -> String {
        var out = ""
        for (pow, coef) in p.sorted(by: { $0.key > $1.key }) where coef != 0 {
            let a = Swift.abs(coef)
            let num = a == a.rounded() && a < 1e9 ? String(Int(a)) : String(a)
            var body: String
            switch pow {
            case 0: body = num
            case 1: body = (a == 1 ? "" : num) + "x"
            default: body = (a == 1 ? "" : num) + "x^{\(pow)}"
            }
            if out.isEmpty {
                body = (coef < 0 ? "-" : "") + body
            } else {
                body = (coef < 0 ? "-" : "+") + body
            }
            out += body
        }
        return out.isEmpty ? "0" : out
    }

    // MARK: - 翻译（只有这一小段是"逻辑"）

    struct Mapped {
        var kind: String
        var expected: String?
        var explanation: String?
    }

    /// 学生把原函数里的项原样抄下来没求导 → `not_differentiated`（课上最常错的一种）；
    /// 系数不对 → `wrong_coef`；整行抄了原函数 → `not_differentiated`；其余沿用 MathEngine 的码。
    static func classify(_ e: MathEngine.AnnotationError, index: Int?,
                         student: MathEngine.StudentLine?, function: MathEngine.Poly?) -> Mapped {
        var kind = e.kind
        var expected = e.expectedLatex.map(MathEngine.LatexText.compactExponents)
        var explanation: String?

        if let i = index, let student, i < student.terms.count, let function {
            let t = student.terms[i]
            if function.coef(of: t.pow) == t.coef, e.kind != "missing_term" {
                kind = "not_differentiated"
                expected = MathEngine.LatexRender.compactTerm(coef: t.coef * MathEngine.Rational(t.pow),
                                                              pow: Swift.max(t.pow - 1, 0))
                explanation = Explanation.derivative(coef: t.coef.doubleValue, pow: t.pow)
            }
        }
        if kind == "wrong_coefficient" { kind = "wrong_coef" }
        if kind == "not_derivative" {
            kind = "not_differentiated"
            explanation = e.explanation
        }
        return Mapped(kind: kind, expected: expected, explanation: explanation)
    }
}
