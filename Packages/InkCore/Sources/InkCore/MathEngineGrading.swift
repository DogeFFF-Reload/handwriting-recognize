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
