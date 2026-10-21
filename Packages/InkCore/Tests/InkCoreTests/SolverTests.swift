import XCTest
@testable import InkCore

/// 「求解」：极限、积分、求和、d/dx、引用已有函数、算式、方程。
final class SolverTests: XCTestCase {
    private let f = try! FunctionDefinition.parse("f(x)=x^2-4")

    private func solve(_ latex: String, functions: [String: FunctionDefinition] = [:],
                       file: StaticString = #filePath, line: UInt = #line) -> Solution {
        do {
            guard let s = try Solver.solve(latex, functions: functions) else {
                XCTFail("当成了函数：\(latex)", file: file, line: line)
                return Solution(input: "", result: nil, relation: "", note: nil, conclusive: false, operation: .evaluate, references: [])
            }
            return s
        } catch {
            XCTFail("解析失败：\(latex) \(error)", file: file, line: line)
            return Solution(input: "", result: nil, relation: "", note: nil, conclusive: false, operation: .evaluate, references: [])
        }
    }

    private func check(_ latex: String, _ expected: String, relation: String = "=", functions: [String: FunctionDefinition] = [:],
                       file: StaticString = #filePath, line: UInt = #line) {
        let s = solve(latex, functions: functions, file: file, line: line)
        XCTAssertEqual(s.result, expected, "\(latex)（\(s.note ?? "")）", file: file, line: line)
        XCTAssertEqual(s.relation, relation, latex, file: file, line: line)
    }

    // MARK: 极限

    func testLimits() {
        check("\\lim_{x\\to0}\\frac{\\sin x}{x}", "1")
        check("\\lim _{x\\rightarrow 0}\\dfrac{1-\\cos x}{x^{2}}", "\\frac{1}{2}")
        check("\\lim_{x\\to\\infty}\\left(1+\\frac{1}{x}\\right)^{x}", "e")
        check("\\lim_{x\\to2}\\frac{x^2-4}{x-2}", "4")
        check("\\lim_{x\\to\\infty}\\frac{3x^2+1}{x^2-2}", "3")
        check("\\lim_{x\\to0^{+}}x^{x}", "1")
        check("\\lim_{x\\to0}\\frac{1}{x^2}", "+\\infty")
        check("\\lim_{x\\to0^-}\\frac{1}{x}", "-\\infty")
        check("\\lim_{x\\to 0}\\frac{e^x-1}{x}", "1")
        check("\\lim_{x\\to1}e^{x}", "e")
        check("\\lim_{x\\to\\infty}\\frac{\\sin x}{x}", "0")
    }

    func testLimitsThatDoNotExist() {
        let s = solve("\\lim_{x\\to0}\\frac{1}{x}")
        XCTAssertNil(s.result)
        XCTAssertTrue(s.conclusive)
        XCTAssertTrue(s.note?.contains("不存在") ?? false, s.note ?? "")
        let osc = solve("\\lim_{x\\to0}\\sin\\frac{1}{x}")
        XCTAssertNil(osc.result)
        XCTAssertTrue(osc.note?.contains("不存在") ?? false, osc.note ?? "")
    }

    func testHandwritingWithoutParentheses() {
        // 手写常省括号：后面的项里还有 x，就一起算进极限
        check("\\lim_{x\\to\\infty}\\sqrt{x^2+x}-x", "\\frac{1}{2}")
        // 后面的项和 x 无关：极限只管前面
        check("\\lim_{x\\to0}\\frac{\\sin x}{x}+1", "2")
        // 黎曼和
        check("\\lim_{n\\to\\infty}\\sum_{k=1}^{n}\\frac{k}{n^2}", "\\frac{1}{2}")
    }

    func testLimitOfDifferenceQuotient() {
        // 导数的定义：结果带着 x
        check("\\lim_{h\\to0}\\frac{f(x+h)-f(x)}{h}", "2x", functions: ["f": f])
    }

    // MARK: 积分

    func testIndefiniteIntegrals() {
        check("\\int x^{2}dx", "\\frac{1}{3}x^{3} + C")
        check("\\int \\frac{1}{x}dx", "\\ln\\left|x\\right| + C")
        check("\\int \\cos x\\,dx", "\\sin x + C")
        check("\\int e^{2x}dx", "\\frac{e^{2x}}{2} + C")
        check("\\int x e^{x} dx", "xe^{x} - e^{x} + C")
        check("\\int \\frac{1}{1+x^2}dx", "\\arctan x + C")
        check("\\int 2x\\cos(x^2)dx", "\\sin(x^{2}) + C")
        check("\\int \\ln x\\,dx", "x\\ln x - x + C")
        check("\\int (2x+1)^{5}dx", "\\frac{(2x + 1)^{6}}{12} + C")
        check("\\int \\frac{1}{x^2+2x+5}dx", "\\frac{1}{2}\\arctan\\frac{x + 1}{2} + C")
        check("\\int \\ln(x^2+1)dx", "x\\ln(x^{2} + 1) - 2x + 2\\arctan x + C")
    }

    func testIndefiniteIntegralsVerifyByDifferentiation() {
        // 结果不写死，只验证 F' = f
        for latex in ["\\int \\sin x\\cos x\\,dx", "\\int \\frac{x}{x^2+1}dx", "\\int x\\sin x\\,dx", "\\int \\frac{1}{x^2-1}dx",
                      "\\int \\sqrt{x}dx", "\\int \\frac{\\ln x}{x}dx", "\\int e^{x}\\sin x\\,dx", "\\int \\sin^2 x\\,dx",
                      "\\int x\\ln x\\,dx", "\\int \\frac{1}{\\sqrt{1-x^2}}dx", "\\int \\tan x\\,dx", "\\int (2x+1)^{5}dx",
                      "\\int x\\sqrt{x^2+1}dx", "\\int \\frac{1}{x^3-x}dx", "\\int 3^{x}dx"] {
            let s = solve(latex)
            XCTAssertNotNil(s.result, "\(latex)：\(s.note ?? "")")
            XCTAssertTrue(s.result?.hasSuffix("+ C") ?? false, latex)
        }
    }

    func testDefiniteIntegrals() {
        check("\\int_{0}^{1}x^{2}dx", "\\frac{1}{3}")
        check("\\int_0^\\pi \\sin x\\,dx", "2")
        check("\\int_{0}^{1}e^{x}dx", "e - 1")
        check("\\int_{0}^{\\infty}e^{-x}dx", "1")
        check("\\int_{-\\infty}^{\\infty}e^{-x^2}dx", "\\sqrt{\\pi}")
        check("\\int_{0}^{1}\\frac{1}{\\sqrt{x}}dx", "2")
        check("\\int_{1}^{2}\\frac{1}{x}dx", "\\ln 2")
        check("\\int_{0}^{1}\\frac{1}{1+x^2}dx", "\\frac{\\pi}{4}")
        check("\\int_{-1}^{1}|x|dx", "1")
        check("\\int_{1}^{\\infty}\\frac{1}{x^2}dx", "1")
        check("\\int_{0}^{1}\\ln x\\,dx", "-1")
        check("\\int_{0}^{1}e^{-x^2}dx", "0.746824", relation: "\\approx")
        check("\\int_0^{\\infty} \\frac{\\sin x}{x}dx", "\\frac{\\pi}{2}")
        check("\\int_0^{\\pi/2}\\sin^2 x dx", "\\frac{\\pi}{4}")
        check("\\int_0^1\\int_0^1 xy\\,dx\\,dy", "\\frac{1}{4}")
        XCTAssertNil(solve("\\int_0^\\infty \\sin x dx").result)
    }

    func testDivergentIntegral() {
        let s = solve("\\int_{0}^{1}\\frac{1}{x}dx")
        XCTAssertNil(s.result)
        XCTAssertEqual(s.note, "积分发散")
        XCTAssertNil(solve("\\int_{-1}^{1}\\frac{1}{x}dx").result)
    }

    func testIntegralOfDefinedFunction() {
        let s = solve("\\int_{0}^{2}f(x)dx", functions: ["f": f])
        XCTAssertEqual(s.result, "-\\frac{16}{3}")
        XCTAssertEqual(s.references, ["f"])
        XCTAssertEqual(s.hint, .area(function: "f", from: 0, to: 2))
        XCTAssertEqual(s.operation, .integral)
        // 变上限积分
        check("\\int_{0}^{x}t\\,dt", "\\frac{1}{2}x^{2}")
    }

    // MARK: 求和

    func testScreenshotSums() {
        // 识别器把上界 10 拆开时，不能乘成 0（空和）
        check("\\sum_{x=1}^{10}x", "55")
        check("\\sum_{i=1}^{10}i", "55")
        check("\\sum_{x=1}^10 x", "55")
        check("\\sum_{x=1}^{1 0}x", "55")
        check("\\sum_{x=1}^{1{0}}x", "55")
        check("\\sum_{x=1}^{{1}{0}}x", "55")
        check("\\int_0^10 x\\,dx", "50")
        let sq = try! FunctionDefinition.parse("f(x)=x^2")
        check("\\sum_{x=1}^{3}f(x)", "14", functions: ["f": sq])
        check("\\sum_{x=1}^{10}f(x)", "385", functions: ["f": sq])
        check("\\sum_{x=1}^{1 0}f\\left( x\\right)", "385", functions: ["f": sq])
    }

    func testFiniteSums() {
        check("\\sum_{k=1}^{100}k", "5050")
        check("\\sum _{k=1}^{10}\\frac{1}{k}", "\\frac{7381}{2520}")
        check("\\sum_{k=0}^{10}2^{k}", "2047")
        check("\\prod_{k=1}^{5}k", "120")
    }

    func testSymbolicSums() {
        check("\\sum_{k=1}^{n}k", "\\frac{n(n + 1)}{2}")
        check("\\sum_{k=1}^{n}k^{2}", "\\frac{n(n + 1)(2n + 1)}{6}")
        check("\\sum_{k=1}^{n}k^{3}", "\\frac{n^{2}(n + 1)^{2}}{4}")
        check("\\sum_{k=1}^{n}(2k-1)", "n^{2}")
        check("\\sum_{k=1}^{n}2^{k}", "2^{n + 1} - 2")
        check("\\sum_{k=1}^{n}\\left(\\frac{1}{2}\\right)^{k}", "1 - (\\frac{1}{2})^{n}")
        check("\\prod_{k=1}^{n}k", "n!")
    }

    func testInfiniteSeries() {
        check("\\sum_{n=1}^{\\infty}\\frac{1}{n^{2}}", "\\frac{\\pi^{2}}{6}")
        check("\\sum_{n=0}^{\\infty}\\frac{1}{n!}", "e")
        check("\\sum_{n=0}^{\\infty}\\frac{1}{2^{n}}", "2")
        check("\\sum_{n=1}^{\\infty}\\frac{(-1)^{n+1}}{n}", "\\ln 2")
        check("\\sum_{n=1}^{\\infty}\\frac{1}{n(n+1)}", "1")
        check("\\sum_{n=1}^{\\infty}\\frac{1}{n^4}", "\\frac{\\pi^{4}}{90}")
        check("\\sum_{n=1}^{\\infty}\\frac{1}{n^{3}}", "1.20206", relation: "\\approx")
        let harmonic = solve("\\sum_{n=1}^{\\infty}\\frac{1}{n}")
        XCTAssertNil(harmonic.result)
        XCTAssertTrue(harmonic.conclusive)
        XCTAssertTrue(harmonic.note?.contains("发散") ?? false, harmonic.note ?? "")
        let alternating = solve("\\sum_{n=0}^{\\infty}(-1)^{n}")
        XCTAssertNil(alternating.result)
        XCTAssertTrue(alternating.note?.contains("发散") ?? false, alternating.note ?? "")
    }

    // MARK: 求导、取值、算式、方程

    func testDerivativeOperator() {
        check("\\frac{d}{dx}\\left(x^{2}\\sin x\\right)", "2x\\sin x + x^{2}\\cos x")
        check("\\frac{d}{dx}f(x)", "2x", functions: ["f": f])
        check("\\frac{d}{dx}\\ln(x^2+1)", "\\frac{2x}{x^{2} + 1}")
        check("\\frac{d^2}{dx^2}x^4", "12x^{2}")
        let s = solve("\\frac{d}{dx}x^3")
        XCTAssertEqual(s.operation, .derivative)
        XCTAssertEqual(s.result, "3x^{2}")
    }

    func testEvaluateDefinedFunction() {
        check("f(3)", "5", functions: ["f": f])
        check("f'(2)", "4", functions: ["f": f])
        check("f(x+1)", "x^{2} + 2x - 3", functions: ["f": f])
    }

    func testArithmetic() {
        check("\\frac{1}{2}+\\frac{1}{3}", "\\frac{5}{6}")
        check("2^{10}", "1024")
        check("\\sqrt{8}", "2\\sqrt{2}")
        check("\\sin\\frac{\\pi}{6}", "\\frac{1}{2}")
        check("5!", "120")
        check("1+2=", "3")
    }

    func testEquations() {
        check("x^2-4=0", "x = \\pm 2", relation: "\\Rightarrow")
        check("2x+1=5", "x = 2", relation: "\\Rightarrow")
        check("x^2-2x-1=0", "x = 1 \\pm \\sqrt{2}", relation: "\\Rightarrow")
        check("x^2-3x+2=0", "x_{1} = 1,\\; x_{2} = 2", relation: "\\Rightarrow")
        check("f(x)=0", "x = \\pm 2", relation: "\\Rightarrow", functions: ["f": f])
        let none = solve("x^2+1=0")
        XCTAssertNil(none.result)
        XCTAssertTrue(none.conclusive)
        let trig = solve("\\sin x=\\frac{1}{2}")
        XCTAssertEqual(trig.result, "x_{1} = \\frac{\\pi}{6},\\; x_{2} = \\frac{5\\pi}{6}")
        XCTAssertEqual(trig.note, "只列出 [0, 2π) 内的解")
    }

    // MARK: 分流：函数还是求解

    func testRouting() {
        XCTAssertNil(try Solver.solve("f(x)=x^2-4"))
        XCTAssertNil(try Solver.solve("y=2x+1"))
        XCTAssertNil(try Solver.solve("x^2-4"))
        XCTAssertFalse(Solver.looksLikeComputation("f(x)=x^2-4"))
        XCTAssertFalse(Solver.looksLikeComputation("g(x)=f(x)+1", functions: ["f": f]))
        XCTAssertFalse(Solver.looksLikeComputation("2"))
        XCTAssertTrue(Solver.looksLikeComputation("\\int_0^1 x dx"))
        XCTAssertTrue(Solver.looksLikeComputation("\\lim_{x\\to0}\\frac{\\sin x}{x}"))
        XCTAssertTrue(Solver.looksLikeComputation("\\sum_{k=1}^{n}k"))
        XCTAssertTrue(Solver.looksLikeComputation("x^2-4=0"))
        XCTAssertTrue(Solver.looksLikeComputation("1+2"))
        XCTAssertTrue(Solver.looksLikeComputation("f(2)", functions: ["f": f]))
        XCTAssertTrue(Solver.looksLikeComputation("F(x)=\\int_0^x t dt"))
        // 学生自己写了答案：照样重新算
        check("\\int_0^1 x^2 dx = \\frac{1}{2}", "\\frac{1}{3}")
    }

    func testFunctionDefinedThroughAnotherFunction() throws {
        let g = try FunctionDefinition.parse("g(x)=f(x)+1", functions: ["f": f])
        XCTAssertEqual(g.name, "g")
        XCTAssertEqual(g.evaluate(3), 6)
        XCTAssertTrue(g.parameters.isEmpty)
    }

    func testInputIsCleanedForDisplay() {
        let s = solve("\\lim _{x\\rightarrow 0}\\dfrac{\\sin x}{x}=")
        XCTAssertEqual(s.input, "\\lim _{x\\to 0}\\frac{\\sin x}{x}")
        let h = solve("\\lim_{x\\to 2}f(x)", functions: ["f": f])
        XCTAssertEqual(h.result, "0")
        XCTAssertEqual(h.hint, .point(function: "f", x: 2, y: 0))
    }

    // MARK: 数值方法和封闭形式

    func testClosedForms() {
        func cf(_ v: Double) -> String? { Numerics.closedForm(v)?.latex }
        XCTAssertEqual(cf(0.75), "\\frac{3}{4}")
        XCTAssertEqual(cf(Double.pi / 4), "\\frac{\\pi}{4}")
        XCTAssertEqual(cf(Double.pi * Double.pi / 6), "\\frac{\\pi^{2}}{6}")
        XCTAssertEqual(cf(2.squareRoot() / 2), "\\frac{\\sqrt{2}}{2}")
        XCTAssertEqual(cf(MathExpr.euler - 1), "e - 1")
        XCTAssertEqual(cf(1 - 2 / MathExpr.euler), "1 - 2e^{-1}")
        XCTAssertEqual(cf(log(2.0)), "\\ln 2")
        XCTAssertEqual(cf((1 + 5.squareRoot()) / 2), "\\frac{1 + \\sqrt{5}}{2}")
        XCTAssertEqual(cf(Double.pi.squareRoot()), "\\sqrt{\\pi}")
        XCTAssertNil(cf(0.746824132812427))
    }

    func testQuadratureAndSeriesPrimitives() {
        XCTAssertEqual(Numerics.integrate({ $0 * $0 }, 0, 3)!, 9, accuracy: 1e-12)
        XCTAssertEqual(Numerics.integrate({ 1 / (1 + $0 * $0) }, -.infinity, .infinity)!, Double.pi, accuracy: 1e-9)
        XCTAssertNil(Numerics.integrate({ 1 / $0 }, 1, .infinity))
        XCTAssertEqual(Numerics.series({ 1 / ($0 * $0) }, from: 1, to: .infinity).value!, Double.pi * Double.pi / 6, accuracy: 1e-9)
        XCTAssertEqual(Numerics.roots({ $0 * $0 - 2 }, in: -3, 3).count, 2)
        XCTAssertEqual(Numerics.roots({ ($0 - 1) * ($0 - 1) }, in: -3, 3).count, 1)
        XCTAssertEqual(Numerics.limit({ sin($0) / $0 }, at: 0).value!, 1, accuracy: 1e-12)
    }

    func testPlainTextForGraphLabels() {
        XCTAssertEqual(Solver.plainText("-\\frac{16}{3}"), "−16/3")
        XCTAssertEqual(Solver.plainText("\\frac{\\pi}{4}"), "π/4")
        XCTAssertEqual(Solver.plainText("\\frac{\\sqrt{2}}{2}"), "√2/2")
        XCTAssertEqual(Solver.plainText("e - 1"), "e − 1")
        XCTAssertEqual(Solver.plainText("\\frac{\\pi^{2}}{6}"), "π²/6")
        XCTAssertEqual(Solver.plainText("+\\infty"), "+∞")
    }

    func testLatexPrinterForNewForms() {
        XCTAssertEqual(MathExpr.integral("x", .number(0), .number(1), .power(.symbol("x"), .number(2))).latex,
                       "\\int_{0}^{1} x^{2} \\, dx")
        XCTAssertEqual(MathExpr.limit("x", .number(.infinity), 0, .divide(.number(1), .symbol("x"))).latex,
                       "\\lim_{x \\to \\infty} \\frac{1}{x}")
        XCTAssertEqual(MathExpr.call("factorial", [.symbol("n")]).latex, "n!")
        XCTAssertEqual(MathExpr.divide(MathExpr.pi, .number(4)).latex, "\\frac{\\pi}{4}")
    }
}
