import XCTest
@testable import InkCore

/// 千问识别「求解」类式子的真实输出（2026-10-21，qwen3.8-flash，tools/recog-bench/solve_bench.py 生成的手写风格图），
/// 喂给 App 的求解器，看能不能算出来。识别对了但求解器不认那种写法，演示时一样会失败，所以两段一起测。
final class QwenSolveTests: XCTestCase {
    /// 现在的 recognitionPrompt 下的原样输出：21 条全对，F2、F3 是故意写错的，被照抄了（没被「改对」）。
    static let promptV2: [(id: String, latex: String)] = [
        ("F1", #"f(x)=x^{3}-5x"#),
        ("F2", #"f'(x)=3x^{2}-3x"#),
        ("F3", #"\int_{0}^{1}2xdx=2"#),
        ("I1", #"\int_{0}^{1} x^{2} dx"#),
        ("I2", #"\int x e^{x} dx"#),
        ("I3", #"\int_{0}^{\infty} e^{-x} dx"#),
        ("I4", #"\int_{1}^{e}\frac{1}{x}dx"#),
        ("L1", #"\lim_{x \to 0} \frac{\sin x}{x}"#),
        ("L2", #"\lim_{x \to \infty} (1+\frac{1}{x})^{x}"#),
        ("L3", #"\lim_{x \to 2} \frac{x^2 - 4}{x - 2}"#),
        ("L4", #"\lim_{x \to 0^{+}} x \ln x"#),
        ("S1", #"\sum_{k=1}^{n} k^{2}"#),
        ("S2", #"\sum_{n=1}^{\infty} \frac{1}{n^2}"#),
        ("S3", #"\prod_{k=1}^{5} k"#),
        ("S4", #"\sum_{k=1}^{10} 2k"#),
        ("D1", #"\frac{d}{dx}(x^{2}\sin x)"#),
        ("E1", #"x^{2}-5x+6=0"#),
        ("M1", #"\begin{pmatrix}1 & 2 \\ 3 & 4\end{pmatrix}\begin{pmatrix}5 & 6 \\ 7 & 8\end{pmatrix}"#),
        ("M2", #"\begin{pmatrix}2 & 1 \\ 1 & 1\end{pmatrix}"#),
        ("M3", #"\begin{vmatrix}1 & 2 & 3 \\ 0 & 1 & 4 \\ 5 & 6 & 0\end{vmatrix}"#),
        ("M4", #"\begin{bmatrix}1 & 0 & 2 \\ -1 & 3 & 1\end{bmatrix}"#),
    ]

    /// 旧提示词（只说「照抄」）下写法不一样的几条。提示词压不住时 canonicalLatex 兜底，这些也要能算。
    static let promptV1: [(id: String, latex: String)] = [
        ("L1", #"\lim_{x\rightarrow0}\frac{\sin x}{x}"#),
        ("L2", #"\operatorname*{lim}_{x\rightarrow\infty}\left(1+\frac{1}{x}\right)^{x}"#),
        ("L3", #"\lim_{x \rightarrow 2} \frac{x^2 - 4}{x - 2}"#),
        ("L4", #"\lim_{x\rightarrow0^{+}}x\ln x"#),
        ("M1", #"\left( \begin{array} { c c } { 1 } & { 2 } \\ { 3 } & { 4 } \end{array} \right) \left( \begin{array} { c c } { 5 } & { 6 } \\ { 7 } & { 8 } \end{array} \right)"#),
        ("M2", #"\left( \begin{array} { l l } { 2 } & { 1 } \\ { 1 } & { 1 } \end{array} \right)"#),
        ("M3", #"\left| \begin{array} { l l l } { 1 } & { 2 } & { 3 } \\ { 0 } & { 1 } & { 4 } \\ { 5 } & { 6 } & { 0 } \end{array} \right|"#),
        ("M4", #"\left[ \begin{array} { l l l } { 1 } & { 0 } & { 2 } \\ { - 1 } & { 3 } & { 1 } \end{array} \right]"#),
    ]

    private func m(_ rows: String) -> String { #"\begin{pmatrix}"# + rows + #"\end{pmatrix}"# }

    private func tex(_ id: String, _ list: [(id: String, latex: String)]) -> String {
        list.first { $0.id == id }!.latex
    }

    private func solve(_ latex: String, file: StaticString = #filePath, line: UInt = #line) -> Solution? {
        do {
            return try Solver.solve(canonicalLatex(latex))
        } catch {
            XCTFail("解析失败：\(latex) \(error)", file: file, line: line)
            return nil
        }
    }

    func testSolveOutputsFromCurrentPrompt() {
        let exact: [String: String] = [
            "I1": #"\frac{1}{3}"#, "I2": "xe^{x} - e^{x} + C", "I3": "1",
            "L1": "1", "L2": "e", "L3": "4", "E1": #"x_{1} = 2,\; x_{2} = 3"#,
        ]
        for (id, latex) in Self.promptV2 where !id.hasPrefix("M") && !id.hasPrefix("F") {
            let s = solve(latex)
            XCTAssertNotNil(s?.result, "\(id) \(latex) 没算出来：\(s?.note ?? "")")
            if let e = exact[id] { XCTAssertEqual(s?.result, e, id) }
        }
    }

    func testMatricesFromCurrentPrompt() {
        let v2 = Self.promptV2
        XCTAssertTrue(MatrixMath.contains(tex("M1", v2)))
        XCTAssertEqual(MatrixMath.solve(tex("M1", v2), action: .calculate).result, m(#"19 & 22 \\ 43 & 50"#))
        XCTAssertEqual(MatrixMath.solve(tex("M2", v2), action: .inverse).result, m(#"1 & -1 \\ -1 & 2"#))
        XCTAssertEqual(MatrixMath.solve(tex("M3", v2), action: .determinant).result, "1")
        XCTAssertTrue(MatrixMath.contains(tex("M4", v2)))
    }

    func testCanonicalLeavesConformingOutputAlone() {
        for (id, latex) in Self.promptV2 {
            XCTAssertEqual(canonicalLatex(latex), latex, id)
        }
    }

    func testOldStyleLimitsAreCanonicalized() {
        for id in ["L1", "L2", "L3", "L4"] {
            let c = canonicalLatex(tex(id, Self.promptV1))
            XCTAssertFalse(c.contains("operatorname") || c.contains("rightarrow"), c)
            XCTAssertNotNil(solve(c)?.result, "\(id) \(c)")
        }
        XCTAssertEqual(canonicalLatex(tex("L2", Self.promptV1)), #"\lim_{x\to\infty}\left(1+\frac{1}{x}\right)^{x}"#)
        XCTAssertEqual(solve(tex("L2", Self.promptV1))?.result, "e")
    }

    func testOldStyleMatricesAreCanonicalized() {
        let v1 = Self.promptV1
        XCTAssertEqual(canonicalLatex(tex("M2", v1)), m(#"2 & 1 \\ 1 & 1"#))
        XCTAssertEqual(canonicalLatex(tex("M3", v1)), #"\begin{vmatrix}1 & 2 & 3 \\ 0 & 1 & 4 \\ 5 & 6 & 0\end{vmatrix}"#)
        XCTAssertEqual(canonicalLatex(tex("M4", v1)), #"\begin{bmatrix}1 & 0 & 2 \\ -1 & 3 & 1\end{bmatrix}"#)
        XCTAssertFalse(canonicalLatex(tex("M1", v1)).contains("array"))
        XCTAssertEqual(MatrixMath.solve(canonicalLatex(tex("M1", v1)), action: .calculate).result, m(#"19 & 22 \\ 43 & 50"#))
        XCTAssertEqual(MatrixMath.solve(canonicalLatex(tex("M2", v1)), action: .inverse).result, m(#"1 & -1 \\ -1 & 2"#))
        XCTAssertEqual(MatrixMath.solve(canonicalLatex(tex("M3", v1)), action: .determinant).result, "1")
    }
}
