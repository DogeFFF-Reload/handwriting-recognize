import Foundation
import XCTest
@testable import InkCore

/// 函数这一步：识别结果 → 能画的函数；双击时的分段；识别器的兜底顺序。
final class FunctionDefinitionTests: XCTestCase {
    private func f(_ latex: String) throws -> FunctionDefinition { try FunctionDefinition.parse(latex) }

    func testGoldenLinesInTheFormsRecognizersGive() throws {
        // MyScript 的 LaTeX 带 \left( \right) 和 ^{}；Qwen 一般是紧凑写法
        for latex in ["f\\left( x\\right) =x^{3}-5x", "f(x)=x^3-5x", "f(x) = x^{3} - 5 x", "$f(x)=x^3-5x$"] {
            let d = try f(latex)
            XCTAssertEqual(d.name, "f", latex)
            XCTAssertEqual(d.variable, "x", latex)
            XCTAssertEqual(d.polynomial, [3: 1, 1: -5], latex)
            XCTAssertEqual(d.evaluate(2), -2, accuracy: 1e-12, latex)
        }
        XCTAssertEqual(try f("y=x^3-3x").polynomial, [3: 1, 1: -3])
        XCTAssertEqual(try f("x^{2}+1").name, "f", "只写右边也当作 f(x)")
    }

    func testImplicitMultiplicationAndExpansion() throws {
        XCTAssertEqual(try f("f(x)=(x+1)(x-1)").polynomial, [2: 1, 0: -1])
        XCTAssertEqual(try f("f(x)=2x(x-3)").polynomial, [2: 2, 1: -6])
        XCTAssertEqual(try f("f(x)=\\frac{1}{2}x^{2}").polynomial, [2: 0.5])
        XCTAssertEqual(try f("f(x)=3\\cdot x^2").polynomial, [2: 3])
        XCTAssertEqual(try f("f(x)=(x-1)^{2}").polynomial, [2: 1, 1: -2, 0: 1])
        XCTAssertEqual(try f("f(x)=x^23").polynomial, [2: 3], "不带括号的上标只取一个字符")
        XCTAssertEqual(try f("f(x)=x²−4").polynomial, [2: 1, 0: -4])
    }

    func testElementaryFunctions() throws {
        XCTAssertEqual(try f("f(x)=\\sin x").evaluate(.pi / 2), 1, accuracy: 1e-12)
        XCTAssertEqual(try f("f(x)=2\\sin 2x+1").evaluate(.pi / 4), 3, accuracy: 1e-12, "\\sin 2x 是 sin(2x)")
        XCTAssertEqual(try f("f(x)=\\sin x\\cos x").evaluate(.pi / 4), 0.5, accuracy: 1e-12)
        XCTAssertEqual(try f("f(x)=\\sin^{2}x+\\cos^2x").evaluate(0.7), 1, accuracy: 1e-12)
        XCTAssertEqual(try f("f(x)=e^{x}").evaluate(1), MathExpr.euler, accuracy: 1e-12)
        XCTAssertEqual(try f("f(x)=\\ln(x)").evaluate(MathExpr.euler), 1, accuracy: 1e-12)
        XCTAssertEqual(try f("f(x)=\\log_{2}x").evaluate(8), 3, accuracy: 1e-12)
        XCTAssertEqual(try f("f(x)=\\sqrt{x}").evaluate(9), 3, accuracy: 1e-12)
        XCTAssertEqual(try f("f(x)=\\sqrt[3]{x}").evaluate(-8), -2, accuracy: 1e-12, "负数开立方")
        XCTAssertEqual(try f("f(x)=x^{\\frac{1}{3}}").evaluate(-27), -3, accuracy: 1e-9)
        XCTAssertEqual(try f("f(x)=|x-1|").evaluate(-2), 3, accuracy: 1e-12)
        XCTAssertEqual(try f("f(x)=x|x|").evaluate(-2), -4, accuracy: 1e-12)
        XCTAssertEqual(try f("f(x)=\\frac{1}{x}").evaluate(4), 0.25, accuracy: 1e-12)
        XCTAssertEqual(try f("f(x)=\\dfrac{x+1}{x-1}").evaluate(3), 2, accuracy: 1e-12)
        XCTAssertEqual(try f("f(x)=2\\pi x").evaluate(1), 2 * .pi, accuracy: 1e-12)
        XCTAssertEqual(try f("f(x)=\\operatorname{sin}x").evaluate(.pi / 2), 1, accuracy: 1e-12)
        XCTAssertEqual(try f("f(x)=sinx").evaluate(.pi / 2), 1, accuracy: 1e-12, "识别器把 \\sin 写成了字母")
        XCTAssertEqual(try f("f(x)=\\sin^{-1}x").evaluate(1), .pi / 2, accuracy: 1e-12)
        XCTAssertEqual(try f("y=-x^{2}").evaluate(3), -9, accuracy: 1e-12, "负号比乘方低")
        XCTAssertEqual(try f("y=2^{-x}").evaluate(1), 0.5, accuracy: 1e-12)
        XCTAssertNil(try f("f(x)=\\sin x").polynomial)
    }

    func testOtherLettersBecomeSliders() throws {
        let d = try f("f(x)=ax^{2}+bx+c")
        XCTAssertEqual(d.parameters, ["a", "b", "c"])
        XCTAssertNil(d.polynomial, "带参数时不按多项式系数出滑条")
        XCTAssertEqual(d.evaluate(2, parameters: ["a": 1, "b": -3, "c": 2]), 0, accuracy: 1e-12)
        XCTAssertEqual(d.evaluate(2), 7, accuracy: 1e-12, "没给值的参数按 1")
        let t = try f("g(t)=t^{2}")
        XCTAssertEqual(t.name, "g")
        XCTAssertEqual(t.variable, "t")
        XCTAssertEqual(t.parameters, [])
        XCTAssertEqual(t.evaluate(3), 9, accuracy: 1e-12)
    }

    func testMultilineResultsUseTheFirstLine() throws {
        XCTAssertEqual(try f("\\begin{aligned}&f(x)=x^{2}\\\\ &g(x)=x\\end{aligned}").polynomial, [2: 1])
        XCTAssertEqual(try f("f(x)=x^2 = x\\cdot x").polynomial, [2: 1], "连等只要第一段")
    }

    func testThingsThatAreNotFunctions() {
        XCTAssertThrowsError(try f(""))
        XCTAssertThrowsError(try f("f'(x)=3x^2-3"), "导数行不在这里画")
        XCTAssertThrowsError(try f("x^{2}+y^{2}=1"))
        XCTAssertThrowsError(try f("f(x)=(x+1"))
        XCTAssertThrowsError(try f("f(x)=\\int x"))
    }
}

final class InkSegmenterTests: XCTestCase {
    private func stroke(_ id: String, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, t: Double) -> InkStroke {
        InkStroke(id: id, bounds: CGRect(x: x, y: y, width: w, height: h), createdAt: Date(timeIntervalSince1970: t))
    }

    /// f(x)=x³−5x 写在 y≈100 一行；下一行（隔一条横线）是 f′(x)…
    private lazy var page: [InkStroke] = [
        stroke("f", 40, 90, 22, 48, t: 1), stroke("(", 66, 92, 10, 44, t: 2), stroke("x", 80, 104, 20, 22, t: 3),
        stroke(")", 104, 92, 10, 44, t: 4), stroke("=1", 124, 108, 24, 3, t: 5), stroke("=2", 124, 118, 24, 3, t: 6),
        stroke("x2", 160, 104, 22, 22, t: 7), stroke("3", 186, 84, 12, 18, t: 8), stroke("-", 210, 114, 18, 3, t: 9),
        stroke("5", 240, 100, 16, 26, t: 10), stroke("x3", 262, 104, 20, 22, t: 11),
        stroke("d1", 40, 200, 22, 48, t: 12), stroke("d2", 66, 202, 10, 44, t: 13),
    ]

    func testOneLineIsOneSegmentIncludingTheSuperscript() {
        let seed = InkSegmenter.seed(in: page, near: CGPoint(x: 300, y: 112))!
        XCTAssertEqual(seed.id, "x3")
        let seg = InkSegmenter.cluster(page, from: seed)
        XCTAssertEqual(seg.map(\.id), ["f", "(", "x", ")", "=1", "=2", "x2", "3", "-", "5", "x3"])
    }

    func testNextLineIsSeparate() {
        let seg = InkSegmenter.cluster(page, from: InkSegmenter.seed(in: page, near: CGPoint(x: 60, y: 260))!)
        XCTAssertEqual(seg.map(\.id), ["d1", "d2"])
    }

    func testWithoutAPointTheLastStrokeIsTheSeed() {
        XCTAssertEqual(InkSegmenter.seed(in: page, near: nil)?.id, "d2")
        XCTAssertEqual(InkSegmenter.seed(in: page, near: CGPoint(x: 900, y: 900))?.id, "d2", "落点离笔迹太远时同样取最后一笔")
    }

    func testSketchStrokesThatCrossAreOneSegment() {
        let sketch = [stroke("ab", 400, 300, 120, 200, t: 1), stroke("bc", 400, 490, 260, 12, t: 2),
                      stroke("ca", 510, 300, 150, 200, t: 3), stroke("median", 520, 310, 20, 190, t: 4)]
        XCTAssertEqual(InkSegmenter.cluster(sketch + page, from: sketch[3]).count, 4)
    }
}

final class FallbackRecognizerTests: XCTestCase {
    private struct Fixed: InkRecognizer {
        var latex: String?
        func recognize(line: InkLine, imagePNG: Data?) async throws -> RecognitionResult {
            guard let latex else { throw RecognizerError.badResponse("down") }
            return RecognitionResult(lineID: line.id, revision: line.revision, latex: latex, engine: latex)
        }
    }

    private let line = InkLine(id: "F1", revision: 1, mode: .function, band: .zero, strokes: [], removedStrokeIDs: [])

    func testFirstNonEmptyResultWins() async throws {
        let r = try await FallbackRecognizer([Fixed(latex: nil), Fixed(latex: ""), Fixed(latex: "x^2"), Fixed(latex: "x")])
            .recognize(line: line, imagePNG: nil)
        XCTAssertEqual(r.latex, "x^2")
    }

    func testLastEmptyResultIsReturnedAndAllErrorsThrow() async throws {
        let r = try await FallbackRecognizer([Fixed(latex: nil), Fixed(latex: "")]).recognize(line: line, imagePNG: nil)
        XCTAssertEqual(r.latex, "")
        do {
            _ = try await FallbackRecognizer([Fixed(latex: nil)]).recognize(line: line, imagePNG: nil)
            XCTFail("都失败时应抛错")
        } catch {}
    }

    /// 双击确认后才识别：内置黄金路径不再按笔画数猜，写法和估的笔数不同也给整行。
    func testWholeLineReplayIgnoresTheStrokeCountGuess() async throws {
        let tracker = ReplayTracker()
        let replay = ReplayRecognizer(script: .golden, tracker: tracker, wholeLine: true)
        let ids = (1...12).map { "s\($0)" }   // 只写了 12 笔，估的是 16 笔
        func line(_ ids: [String], rev: Int) -> InkLine {
            InkLine(id: "F1", revision: rev, mode: .function, band: .zero,
                    strokes: ids.map { InkStroke(id: $0, bounds: .zero, createdAt: Date()) }, removedStrokeIDs: [])
        }
        var r = try await replay.recognize(line: line(ids, rev: 1), imagePNG: nil)
        XCTAssertEqual(r.latex, "f(x)=x^3-5x")
        // 还原笔迹，擦掉 5（两笔），写一个 3
        r = try await replay.recognize(line: line(Array(ids.dropLast(2)) + ["s13"], rev: 2), imagePNG: nil)
        XCTAssertEqual(r.latex, "f(x)=x^3-3x")
    }
}
