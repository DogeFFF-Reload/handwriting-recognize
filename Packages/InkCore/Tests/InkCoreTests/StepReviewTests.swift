import XCTest
@testable import InkCore

/// 「检查我这一步」：只圈出有问题的那一项，提示分三级，学生自己点开。
final class StepReviewTests: XCTestCase {
    private func box(_ id: String, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> InkStroke {
        InkStroke(id: id, bounds: CGRect(x: x, y: y, width: w, height: h), createdAt: Date(timeIntervalSince1970: 0))
    }

    /// f'(x)=3x²-3x 的大致笔画外框（和 TermSegmenterTests 的同一行）。
    private var goldenLine: InkLine {
        let row: [InkStroke] = [
            box("f", 10, 100, 20, 60), box("'", 32, 98, 4, 10), box("(", 40, 100, 10, 50), box("x1", 52, 115, 18, 30),
            box(")", 72, 100, 10, 50), box("=a", 90, 120, 26, 2), box("=b", 90, 132, 26, 2),
            box("3", 125, 105, 22, 40), box("x2", 150, 115, 22, 30), box("x2'", 150, 115, 22, 30), box("2", 175, 95, 12, 18),
            box("-", 196, 126, 20, 2),
            box("3b", 222, 105, 22, 40), box("x3", 248, 115, 22, 30), box("x3'", 248, 115, 22, 30),
        ]
        return InkLine(id: "C1", revision: 1, mode: .derivative, band: CGRect(x: 10, y: 95, width: 260, height: 65),
                       strokes: row, removedStrokeIDs: [])
    }

    private func review(_ f: String, _ step: String, file: StaticString = #filePath, line: UInt = #line) -> StepReview.Result? {
        do {
            return try StepReview.review(line: goldenLine, function: FunctionDefinition.parse(f), stepLatex: step)
        } catch {
            XCTFail("\(step)：\(error)", file: file, line: line)
            return nil
        }
    }

    private func problem(_ f: String, _ step: String) -> StepReview.Problem? {
        do {
            _ = try StepReview.review(line: goldenLine, function: FunctionDefinition.parse(f), stepLatex: step)
            return nil
        } catch {
            return error as? StepReview.Problem
        }
    }

    func testAstraExampleCirclesTheLastTermAndAsksAQuestionFirst() throws {
        let r = try XCTUnwrap(review("f(x)=x^3-3x", "f'(x)=3x^2-3x"))
        XCTAssertFalse(r.ok)
        XCTAssertEqual(r.issues.count, 1)
        let issue = r.issues[0]
        XCTAssertEqual(issue.kind, "wrong_term")
        XCTAssertEqual(issue.written, "−3x")
        XCTAssertEqual(issue.hints.first, "一次项求导后，还会带着 x 吗？")
        XCTAssertEqual(issue.hints.count, 3)
        XCTAssertFalse(issue.hints[0].contains("−3。"), "第一级提示不能直接说出答案")
        XCTAssertTrue(issue.hints[2].contains("−3"))
        // 圈的是笔画切出来的第二项（−3x，从 x = 196 到 270），外扩一点
        XCTAssertEqual(issue.box.minX, 188)
        XCTAssertEqual(issue.box.maxX, 278)
        XCTAssertNil(issue.answerLatex, "逐项判时答案写在第三级提示里")
        XCTAssertTrue(r.byTerm)
        XCTAssertEqual(r.answer, "f'(x)=3x^{2} - 3")
    }

    func testCorrectStepIsConfirmed() throws {
        let r = try XCTUnwrap(review("f(x)=x^3-3x", "f'(x)=3x^2-3"))
        XCTAssertTrue(r.ok)
        XCTAssertTrue(r.issues.isEmpty)
    }

    func testRecognizerStyleLatex() throws {
        let r = try XCTUnwrap(review("f\\left( x\\right) =x^{3}-3x", "f^{\\prime}\\left( x\\right) =3x^{2}-3x"))
        XCTAssertEqual(r.issues.map(\.kind), ["wrong_term"])
        let ok = try XCTUnwrap(review("f\\left( x\\right) =x^{3}-3x", "f^{\\prime}\\left( x\\right) =3x^{2}-3"))
        XCTAssertTrue(ok.ok)
    }

    func testCoefficientSignMissingAndExtraTerms() throws {
        let coef = try XCTUnwrap(review("f(x)=x^3", "f'(x)=2x^2"))
        XCTAssertEqual(coef.issues.map(\.kind), ["wrong_coefficient"])
        XCTAssertTrue(coef.issues[0].hints[0].contains("系数"))
        XCTAssertTrue(coef.issues[0].hints[1].contains("指数 3 乘到系数上"))
        XCTAssertTrue(coef.issues[0].hints[2].contains("3x²"))

        let sign = try XCTUnwrap(review("f(x)=x^3-3x", "f'(x)=3x^2+3"))
        XCTAssertEqual(sign.issues.map(\.kind), ["wrong_sign"])
        XCTAssertTrue(sign.issues[0].hints[1].contains("负号"))

        let missing = try XCTUnwrap(review("f(x)=x^3-3x+1", "f'(x)=3x^2"))
        XCTAssertEqual(missing.issues.map(\.kind), ["missing_term"])
        XCTAssertEqual(missing.issues[0].written, "")
        XCTAssertGreaterThan(missing.issues[0].box.minX, goldenLine.band.maxX, "漏项圈在这一行末尾")

        let extra = try XCTUnwrap(review("f(x)=x^2+5", "f'(x)=2x+5"))
        XCTAssertEqual(extra.issues.map(\.kind), ["extra_term"])
        XCTAssertEqual(extra.issues[0].hints[1], "常数求导得 0。")
    }

    func testCopiedFunctionIsNotADerivative() throws {
        let r = try XCTUnwrap(review("f(x)=x^3-3x", "f'(x)=x^3-3x"))
        XCTAssertEqual(r.issues.map(\.kind), ["not_derivative"])
        XCTAssertTrue(r.issues[0].hints[2].contains("3x² − 3"))
    }

    func testProblems() {
        XCTAssertEqual(problem("f(x)=x^2", "f(x)=x^2"), .notADerivative)
        XCTAssertEqual(problem("f(x)=x^2", "f'(x)="), .notADerivative)
        XCTAssertEqual(problem("f(x)=x^2", "f'(x)=2x+?"), .unreadable)
        XCTAssertEqual(problem("f(x)=\\sin x", "f'(x)=\\cos x+a"), .unreadable, "多了别的字母：不下结论")
    }

    // MARK: 整行比数值（P4 的 DerivativeComparison）

    func testNonPolynomialIsJudgedAsAWholeLine() throws {
        let ok = try XCTUnwrap(review("f(x)=x\\sin x", "f'(x)=\\sin x+x\\cos x"))
        XCTAssertTrue(ok.ok)
        XCTAssertFalse(ok.byTerm)

        let wrong = try XCTUnwrap(review("f(x)=x\\sin x", "f'(x)=x\\cos x"))
        XCTAssertFalse(wrong.ok)
        XCTAssertEqual(wrong.issues.map(\.kind), ["whole_line"])
        let hints = wrong.issues[0].hints
        XCTAssertEqual(hints.count, 3)
        XCTAssertFalse(hints[0].contains("cos"), "第一级不说答案")
        XCTAssertTrue(hints[1].contains("乘积"), hints[1])
        XCTAssertTrue(hints[1].contains("(sin x)′ = cos x"), hints[1])
        let answer = try XCTUnwrap(wrong.issues[0].answerLatex)
        XCTAssertTrue(answer.hasPrefix("f'(x)="), answer)
        XCTAssertTrue(answer.contains("\\cos"), answer)
        // 圈的是等号右边（x = 125 起），不是整行
        XCTAssertEqual(wrong.issues[0].box.minX, 117)

        let chain = try XCTUnwrap(review("f(x)=e^{2x}", "f'(x)=e^{2x}"))
        XCTAssertFalse(chain.ok)
        XCTAssertTrue(chain.issues[0].hints[1].contains("eᵘ"), chain.issues[0].hints[1])
        XCTAssertTrue(try XCTUnwrap(review("f(x)=e^{2x}", "f'(x)=2e^{2x}")).ok)
        XCTAssertTrue(try XCTUnwrap(review("f(x)=\\sin(x^2)", "f'(x)=2x\\cos(x^2)")).ok)
        let inner = try XCTUnwrap(review("f(x)=\\sin(x^2)", "f'(x)=\\cos(x^2)"))
        XCTAssertTrue(inner.issues[0].hints[1].contains("链式法则"), inner.issues[0].hints[1])
    }

    func testDerivativeAtAPointAndHigherOrder() throws {
        let at = try XCTUnwrap(review("f(x)=x^3-3x", "f'(2)=9"))
        XCTAssertTrue(at.ok)
        XCTAssertEqual(at.answer, "f'(2)=9")
        let wrongAt = try XCTUnwrap(review("f(x)=x^3-3x", "f'(2)=6"))
        XCTAssertFalse(wrongAt.ok)
        XCTAssertTrue(wrongAt.issues[0].hints[0].contains("x = 2"), wrongAt.issues[0].hints[0])
        XCTAssertTrue(wrongAt.issues[0].hints[1].hasPrefix("先求出导函数"), wrongAt.issues[0].hints[1])
        XCTAssertEqual(wrongAt.issues[0].answerLatex, "f'(2)=9")

        XCTAssertTrue(try XCTUnwrap(review("f(x)=x^3-3x", "f''(x)=6x")).ok)
        let second = try XCTUnwrap(review("f(x)=x^3-3x", "f''(x)=3x^2-3"))
        XCTAssertFalse(second.ok)
        XCTAssertTrue(second.issues[0].hints[0].contains("2 次导"), second.issues[0].hints[0])
    }

    func testSliderDecimalsAndLinesMathEngineCannotRead() throws {
        // 拖过滑条：系数是小数，照样逐项比
        let decimal = try XCTUnwrap(review("f(x)=1.5x^3-2x", "f'(x)=4.5x^2-2"))
        XCTAssertTrue(decimal.ok)
        XCTAssertTrue(decimal.byTerm)
        // 写法 MathEngine 逐项读不出来（\cos 0）：退回整行比数值，不算看不懂
        let odd = try XCTUnwrap(review("f(x)=x^3-3x", "f'(x)=3x^2-3\\cos 0"))
        XCTAssertTrue(odd.ok)
        XCTAssertFalse(odd.byTerm)
    }
}
