import Foundation
import XCTest
@testable import InkCore

/// 求导：写 f(x) = …，在下面写 f'(x)，App 直接求出导函数。
final class DerivativeTests: XCTestCase {
    private func d(_ latex: String, order: Int = 1) throws -> MathExpr {
        let f = try FunctionDefinition.parse(latex)
        var e = f.body
        for _ in 0..<order { e = e.derivative(f.variable) }
        return e
    }

    func testTextbookResultsReadLikeATextbook() throws {
        let cases: [(String, String)] = [
            ("f(x)=x^2-4", "2x"),
            ("f(x)=x^3-3x", "3x^{2} - 3"),
            ("f(x)=x^3-5x", "3x^{2} - 5"),
            ("f(x)=2x+1", "2"),
            ("f(x)=5", "0"),
            ("f(x)=(x+1)(x-1)", "2x"),
            ("f(x)=\\frac{1}{2}x^{2}", "x"),
            ("f(x)=\\sin x", "\\cos x"),
            ("f(x)=\\cos x", "-\\sin x"),
            ("f(x)=\\sin 2x", "2\\cos(2x)"),
            ("f(x)=e^{x}", "e^{x}"),
            ("f(x)=\\ln x", "\\frac{1}{x}"),
            ("f(x)=\\sqrt{x}", "\\frac{1}{2\\sqrt{x}}"),
            ("f(x)=x\\sin x", "\\sin x + x\\cos x"),
            ("f(x)=\\frac{x+1}{x-1}", "-\\frac{2}{(x - 1)^{2}}"),
            ("f(x)=ax^{2}+bx+c", "2ax + b"),
        ]
        for (f, expected) in cases {
            XCTAssertEqual(try d(f).latex, expected, f)
        }
        XCTAssertEqual(try d("f(x)=x^3", order: 2).latex, "6x")
        XCTAssertEqual(try d("f(x)=x^2-4", order: 2).latex, "2")
    }

    /// 难一点的式子不比对写法，只在几个点上和差商比数值。
    func testAgreesWithFiniteDifferences() throws {
        let fs = ["f(x)=e^{x^2}", "f(x)=\\ln(x^2+1)", "f(x)=x^x", "f(x)=\\sin^2x", "f(x)=\\frac{1}{x}", "f(x)=|x|",
                  "f(x)=2^x", "f(x)=\\log_2x", "f(x)=\\arctan x", "f(x)=\\tan x", "f(x)=x^{\\frac{1}{3}}",
                  "f(x)=\\sqrt{x^2+1}", "f(x)=\\frac{\\sin x}{x}", "f(x)=e^{-x}\\cos(3x)", "f(x)=\\sqrt[3]{x}"]
        for latex in fs {
            let f = try FunctionDefinition.parse(latex)
            let df = f.body.derivative(f.variable)
            for x in [0.37, 0.9, 1.6, 2.3] {
                let h = 1e-6
                let numeric = (f.evaluate(x + h) - f.evaluate(x - h)) / (2 * h)
                let symbolic = df.evaluate(["x": x])
                XCTAssertEqual(symbolic, numeric, accuracy: max(1e-4, abs(numeric) * 1e-5), "\(latex) at \(x): \(df.latex)")
            }
        }
    }

    func testReadingWhatTheStudentWroteBelow() {
        XCTAssertEqual(DerivativeRequest.parse("f'(x)"), DerivativeRequest(name: "f", order: 1, variable: "x"))
        XCTAssertEqual(DerivativeRequest.parse("f^{\\prime}\\left( x\\right) ="), DerivativeRequest(name: "f", order: 1, variable: "x"),
                       "MyScript 的写法")
        XCTAssertEqual(DerivativeRequest.parse("f'(x)=3x^{2}-3x"), DerivativeRequest(name: "f", order: 1, variable: "x"),
                       "等号后面写了什么都不看")
        XCTAssertEqual(DerivativeRequest.parse("f''(x)"), DerivativeRequest(name: "f", order: 2, variable: "x"))
        XCTAssertEqual(DerivativeRequest.parse("g^{\\prime\\prime}(t)")?.order, 2)
        XCTAssertEqual(DerivativeRequest.parse("y'"), DerivativeRequest(name: "y", order: 1))
        XCTAssertEqual(DerivativeRequest.parse("F’(x)")?.name, "F")
        XCTAssertEqual(DerivativeRequest.parse("f'(2)")?.point, 2)
        XCTAssertEqual(DerivativeRequest.parse("f'(-\\frac{1}{2})")?.point, -0.5)
        XCTAssertNil(DerivativeRequest.parse("f(x)=x^2-4"), "这是函数，不是求导")
        XCTAssertNil(DerivativeRequest.parse("x^{2}"))
        XCTAssertNil(DerivativeRequest.parse("f'(x+1)"))
    }

    func testLeftHandSideIsWrittenBack() {
        XCTAssertEqual(DerivativeRequest(name: "f", order: 1, variable: "x").lhsLatex(variable: "x"), "f'(x)")
        XCTAssertEqual(DerivativeRequest(name: "f", order: 2).lhsLatex(variable: "x"), "f''(x)")
        XCTAssertEqual(DerivativeRequest(name: "f", order: 1, point: 2).lhsLatex(variable: "x"), "f'(2)")
        XCTAssertEqual(DerivativeRequest(name: "y", order: 1).lhsLatex(variable: "x"), "y'")
        XCTAssertEqual(MathExpr.formatNumber(0.5), "\\frac{1}{2}")
        XCTAssertEqual(MathExpr.formatNumber(-4), "-4")
        XCTAssertEqual(MathExpr.formatNumber(Double.pi), "\\pi")
    }
}
