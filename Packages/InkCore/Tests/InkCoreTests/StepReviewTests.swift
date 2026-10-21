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
            return try StepReview.review(line: goldenLine, functionLatex: f, stepLatex: step)
        } catch {
            XCTFail("\(step)：\(error)", file: file, line: line)
            return nil
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
        XCTAssertEqual(r.answer, "3x^{2}-3")
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
        XCTAssertThrowsError(try StepReview.review(line: goldenLine, functionLatex: "f(x)=x^2", stepLatex: "f(x)=x^2")) {
            XCTAssertEqual($0 as? StepReview.Problem, .notADerivative)
        }
        XCTAssertThrowsError(try StepReview.review(line: goldenLine, functionLatex: "f(x)=x^2", stepLatex: "f'(x)=")) {
            XCTAssertEqual($0 as? StepReview.Problem, .notADerivative)
        }
        XCTAssertThrowsError(try StepReview.review(line: goldenLine, functionLatex: "f(x)=x^3", stepLatex: "f''(x)=6x")) {
            XCTAssertEqual($0 as? StepReview.Problem, .higherOrder)
        }
        XCTAssertThrowsError(try StepReview.review(line: goldenLine, functionLatex: "f(x)=\\sin x", stepLatex: "f'(x)=\\cos x")) {
            XCTAssertEqual($0 as? StepReview.Problem, .unsupportedFunction)
        }
        XCTAssertThrowsError(try StepReview.review(line: goldenLine, functionLatex: "f(x)=x^2", stepLatex: "f'(x)=2x+?")) {
            XCTAssertEqual($0 as? StepReview.Problem, .unreadable)
        }
    }
}
