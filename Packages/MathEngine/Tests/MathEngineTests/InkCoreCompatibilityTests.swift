//
//  InkCoreCompatibilityTests.swift
//  MathEngine
//
//  把团队仓库 `Packages/InkCore/Tests/InkCoreTests/InkCoreTests.swift` 里与判分有关的断言
//  原样搬过来，跑在 MathEngine 上。目的只有一个：**证明替换掉 P3 的临时实现后行为不变**。
//
//  对照关系：
//    InkCore.DerivativeCheck.check(...)        ↔ 这里用 MathEngineAPI.check / 直接解析
//    InkCore.DerivativeCheck.expectedTermCount ↔ MathEngine.DerivativeCheck.expectedTermCount
//    InkCore.LatexTerms.parse(...)             ↔ StudentLine / PolyParser
//    InkCore.Explanation.derivative(...)       ↔ Explain（同样的模板文字）
//
//  改名/改接口时，这份文件红了就说明"换了引擎，P3 的 App 会看到不一样的东西"。
//

import Foundation
import XCTest
@testable import MathEngine

final class InkCoreCompatibilityTests: XCTestCase {

    // MARK: - 对应 InkCore.DerivativeCheckTests

    /// `f'(x)=3x^2-3x`（错）→ 判定 `-3x` 是原函数里抄下来没求导的那一项
    func testGoldenWrongLine() {
        let a = MathEngineAPI.check(CheckRequest(
            mode: "derivative",
            lines: [.init(id: "L2", latex: "f'(x)=3x^2-3x")],
            context: .init(functionLatex: "f(x)=x^3-3x")))
        XCTAssertFalse(a.ok)
        XCTAssertEqual(a.errors.count, 1)
        XCTAssertEqual(a.errors[0].wrongLatex, "-3x")
        XCTAssertEqual(a.errors[0].expectedLatex, "-3")
        XCTAssertEqual(a.errors[0].charSpan, [4, 7])
        // 契约里叫 not_differentiated；引擎内部是 wrong_term，桥负责映射。
        // 这里断言的是"能算出正确项 + 学生原文 + 位置"，这是不变的部分。
        XCTAssertEqual(a.errors[0].kind, "wrong_term")

        // 说明逐字对齐 InkCore.Explanation.derivative(coef: -3, pow: 1)
        XCTAssertEqual(a.errors[0].explanation, "x 求导得 1，所以 −3x 求导后是 −3。")
        XCTAssertEqual(DerivativeCheck.expectedTermCount(functionLatex: "f(x)=x^3-3x"), 2)
    }

    /// 写法变体（花括号上标、`\prime`）和项序颠倒都要判对
    func testGoldenFixedLineAndOrderFree() {
        for (f, d) in [("f(x)=x^{3}-3x", "f^{\\prime}(x)=3x^{2}-3"),
                       ("f(x)=x^3-3x", "f'(x)=-3+3x^2")] {
            let a = MathEngineAPI.check(CheckRequest(
                mode: "derivative", lines: [.init(id: "L", latex: d)],
                context: .init(functionLatex: f)))
            XCTAssertTrue(a.ok, "应判对：\(d)")
        }
    }

    /// 系数错 / 抄项 / 漏项 / 读不出来 —— 四种错法的分类
    func testOtherMistakes() {
        func firstError(_ f: String, _ d: String) -> AnnotationError? {
            MathEngineAPI.check(CheckRequest(mode: "derivative", lines: [.init(id: "L", latex: d)],
                                             context: .init(functionLatex: f))).errors.first
        }
        let a = firstError("f(x)=x^3-3x", "f'(x)=x^2-3")
        XCTAssertEqual(a?.kind, "wrong_coefficient")
        XCTAssertEqual(a?.expectedLatex, "3x^{2}")           // 桥会压成 3x^2

        let b = firstError("f(x)=x^2+5", "f'(x)=2x+5")
        XCTAssertEqual(b?.kind, "extra_term")                // 桥会映射成 not_differentiated（应为 0）
        XCTAssertEqual(b?.wrongLatex, "+5")

        let c = firstError("f(x)=x^3-3x+5", "f'(x)=3x^2")
        XCTAssertEqual(c?.kind, "missing_term")
        XCTAssertEqual(c?.expectedLatex, "-3")

        let d = firstError("f(x)=x^3-3x", "\\int x")
        XCTAssertEqual(d?.kind, "parse_error")
        XCTAssertNil(firstError("f(x)=x^3-3x", "\\int x")?.expectedLatex)
    }

    // MARK: - 对应 InkCore.LatexTermsTests（解析口径）

    func testLatexTermsGoldenLines() throws {
        XCTAssertEqual(try StudentLine.parse("f(x) = x^{3} - 3x").poly.terms.map(\.pow), [3, 1])
        XCTAssertEqual(try StudentLine.parse("f(x) = x^{3} - 3x").poly.terms.map(\.coef),
                       [Rational(1), Rational(-3)])
        let d = try StudentLine.parse("f^{\\prime}(x)=3x^2-3x")
        XCTAssertEqual(d.terms.count, 2)
        XCTAssertEqual(d.terms.map(\.text), ["3x^2", "-3x"])
    }

    func testHalfWrittenAndOddForms() throws {
        // 写到一半（末尾一个减号）也能解析出已有的项，项数 1
        XCTAssertEqual(try StudentLine.parse("f'(x)=3x^2-").terms.count, 1)
        // 分数系数
        XCTAssertEqual(try StudentLine.parse("f(x)=\\frac{1}{2}x^2").poly.coef(of: 2), Rational(1, 2))
        // 乘点
        XCTAssertEqual(try StudentLine.parse("3x^2\\cdot 2").poly.coef(of: 2), Rational(6))
        // 常数
        XCTAssertEqual(try StudentLine.parse("f'(x)=0").poly.coef(of: 0), Rational(0))
        XCTAssertEqual(try StudentLine.parse("f'(x)=0").poly.terms.count, 0)
        // 首项负号
        XCTAssertEqual(try StudentLine.parse("f(x)=-x^3+6x").poly.terms.map(\.coef),
                       [Rational(-1), Rational(6)])
        // 积分不是多项式，应当抛
        XCTAssertThrowsError(try StudentLine.parse("\\int x^2 dx"))
    }

    // MARK: - 桥要用的小工具（现在在引擎里，可测）

    func testCompactExponents() {
        XCTAssertEqual(LatexText.compactExponents("3x^{2}"), "3x^2")
        XCTAssertEqual(LatexText.compactExponents("x^{12}"), "x^12")
        XCTAssertEqual(LatexText.compactExponents("-3"), "-3")
        XCTAssertEqual(LatexRender.compactTerm(coef: Rational(3), pow: 2), "3x^2")
        XCTAssertEqual(LatexRender.compactTerm(coef: Rational(-3), pow: 1), "-3x")
        XCTAssertEqual(LatexRender.compactTerm(coef: Rational(1), pow: 1), "x")
    }

    func testCharSpanToTermIndex() throws {
        let line = try StudentLine.parse("f'(x)=3x^2-3x")
        // "-3x" 在归一化正文 "3x^2-3x" 里是 [4,7)，对应第 2 项（下标 1）
        XCTAssertEqual(line.termIndex(forCharSpan: 4..<7), 1)
        XCTAssertEqual(line.termIndex(forCharSpan: 0..<4), 0)
        XCTAssertNil(line.termIndex(forCharSpan: 9..<12))
    }

    // MARK: - 门禁要的项数（对应 CheckGate.expectedTermCount）

    func testExpectedTermCount() {
        XCTAssertEqual(DerivativeCheck.expectedTermCount(functionLatex: "f(x)=x^3-3x"), 2)
        XCTAssertEqual(DerivativeCheck.expectedTermCount(functionLatex: "f(x)=x^2+5"), 1)
        XCTAssertEqual(DerivativeCheck.expectedTermCount(functionLatex: "x^3-5x"), 2)
        XCTAssertNil(DerivativeCheck.expectedTermCount(functionLatex: "f(x)="))
        XCTAssertNil(DerivativeCheck.expectedTermCount(functionLatex: "\\int x"))
    }
}
