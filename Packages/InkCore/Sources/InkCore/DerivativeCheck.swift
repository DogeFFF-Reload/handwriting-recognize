#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

/// 第二幕的求导批改（多项式逐项比对）。
///
/// 这是 P4 的 MathEngine 到之前的**临时实现**，规则和《Swift 原生方案》第 4 节一致：
/// 解析学生写的右端 → 按次数对齐正确导数 → 多出来的项、系数不对的项记为错。
/// P4 的 MathEngine 到了以后，App 换成它即可；批注的形状（Annotation）不变。
public enum DerivativeCheck {
    public struct Finding: Equatable {
        /// 学生写的第几项（书写顺序），漏项时为 nil。
        public var termIndex: Int?
        public var kind: String          // not_differentiated | wrong_coef | extra_term | missing_term | whole_line
        public var wrongLatex: String
        public var expectedLatex: String
        /// 原函数里对应的那一项（给说明模板用）。
        public var source: (coef: Double, pow: Int)?

        public static func == (a: Finding, b: Finding) -> Bool {
            a.termIndex == b.termIndex && a.kind == b.kind && a.wrongLatex == b.wrongLatex && a.expectedLatex == b.expectedLatex
                && a.source?.coef == b.source?.coef && a.source?.pow == b.source?.pow
        }
    }

    public struct Result: Equatable {
        public var ok: Bool
        public var findings: [Finding]
        public var explanation: String?
    }

    /// 正确导数有几项（门禁 D1 的「预期项数」）。
    public static func expectedTermCount(functionLatex: String) -> Int? {
        let f = LatexTerms.parse(functionLatex)
        guard let terms = f.terms else { return nil }
        return Set(terms.filter { $0.pow > 0 && $0.coef != 0 }.map(\.pow)).count
    }

    public static func check(functionLatex: String, derivativeLatex: String) -> Result? {
        let f = LatexTerms.parse(functionLatex), d = LatexTerms.parse(derivativeLatex)
        guard let fTerms = f.terms, let written = d.terms else { return nil }

        var fByPow: [Int: Double] = [:]
        for t in fTerms { fByPow[t.pow, default: 0] += t.coef }
        var correct: [Int: Double] = [:]
        for (k, c) in fByPow where k > 0 && c != 0 { correct[k - 1, default: 0] += c * Double(k) }
        var student: [Int: Double] = [:]
        for t in written { student[t.pow, default: 0] += t.coef }

        let close = { (a: Double, b: Double) in abs(a - b) < 1e-9 }
        let wrongPows = Set(student.keys).union(correct.keys).filter { !close(student[$0] ?? 0, correct[$0] ?? 0) }
        if wrongPows.isEmpty { return Result(ok: true, findings: [], explanation: nil) }

        var findings: [Finding] = []
        for (i, t) in written.enumerated() where wrongPows.contains(t.pow) {
            let kind: String
            var srcPow: Int
            if let fc = fByPow[t.pow], close(fc, t.coef) {
                kind = "not_differentiated"; srcPow = t.pow          // 原样抄下，没求导
            } else if close(correct[t.pow] ?? 0, 0) {
                kind = "extra_term"; srcPow = fByPow[t.pow + 1] != nil ? t.pow + 1 : t.pow
            } else {
                kind = "wrong_coef"; srcPow = t.pow + 1
            }
            if fByPow[srcPow] == nil { srcPow = t.pow + 1 }
            let src = fByPow[srcPow].map { (coef: $0, pow: srcPow) }
            let expCoef = src.map { $0.coef * Double($0.pow) } ?? (correct[t.pow] ?? 0)
            let expPow = src.map { max($0.pow - 1, 0) } ?? t.pow
            findings.append(Finding(termIndex: i, kind: kind, wrongLatex: t.latex,
                                    expectedLatex: latex(coef: src?.pow == 0 ? 0 : expCoef, pow: expPow), source: src))
        }
        let writtenPows = Set(written.map(\.pow))
        for (k, c) in correct.sorted(by: { $0.key > $1.key }) where !writtenPows.contains(k) {
            let e = latex(coef: c, pow: k)
            if findings.contains(where: { $0.expectedLatex == e }) { continue }
            findings.append(Finding(termIndex: nil, kind: "missing_term", wrongLatex: "", expectedLatex: e,
                                    source: fByPow[k + 1].map { (coef: $0, pow: k + 1) }))
        }
        if findings.isEmpty {
            findings.append(Finding(termIndex: nil, kind: "whole_line", wrongLatex: d.rhs, expectedLatex: "", source: nil))
        }
        let first = findings[0]
        let explanation = first.source.map { Explanation.derivative(coef: $0.coef, pow: $0.pow) }
            ?? Explanation.generic(kind: first.kind, wrong: first.wrongLatex, expected: first.expectedLatex)
        return Result(ok: false, findings: findings, explanation: explanation)
    }

    /// 生成批注：错项的框由 `TermSegmenter` 按笔画切出来；切不出就圈整行。
    public static func annotation(line: InkLine, functionLatex: String, derivativeLatex: String,
                                  mode: FeedbackMode = .direct) -> Annotation? {
        guard let r = check(functionLatex: functionLatex, derivativeLatex: derivativeLatex) else { return nil }
        if r.ok { return Annotation(lineID: line.id, revision: line.revision, ok: true, feedbackMode: mode) }
        let count = LatexTerms.parse(derivativeLatex).terms?.count
        let boxes = TermSegmenter.termBoxes(strokes: line.strokes, expectedCount: count)
        let errors = r.findings.map { f -> AnnotationError in
            let box = f.termIndex.flatMap { i in boxes.flatMap { i < $0.count ? $0[i] : nil } } ?? line.band
            return AnnotationError(kind: f.kind, wrongLatex: f.wrongLatex,
                                   expectedLatex: mode == .direct ? f.expectedLatex : nil, bbox: BBox.array(box))
        }
        return Annotation(lineID: line.id, revision: line.revision, ok: false, feedbackMode: mode, errors: errors,
                          explanation: mode == .direct ? r.explanation : nil)
    }

    /// (−3, 0) → "-3"；(3, 2) → "3x^2"；(1, 1) → "x"
    public static func latex(coef: Double, pow: Int) -> String {
        if coef == 0 { return "0" }
        let a = abs(coef)
        let num = a == a.rounded() ? String(Int(a)) : String(format: "%g", a)
        let body: String
        switch pow {
        case 0: body = num
        case 1: body = (a == 1 ? "" : num) + "x"
        default: body = (a == 1 ? "" : num) + "x^\(pow)"
        }
        return (coef < 0 ? "-" : "") + body
    }
}
