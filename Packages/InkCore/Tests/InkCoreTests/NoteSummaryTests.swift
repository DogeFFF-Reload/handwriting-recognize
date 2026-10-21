import XCTest
@testable import InkCore

/// 总结笔记：给 qwen3.8-max 的消息、解析它的回复、没有 Key 时的本地要点。
final class NoteSummaryTests: XCTestCase {
    private let digest = NoteDigest(title: "函数与导数", lines: [
        .init(kind: .function, text: "f\\left( x\\right) =x^{2}-4"),
        .init(kind: .derivative, text: "f'(x)=\\;\\color{#1E9E62}{2x}"),
        .init(kind: .solution, text: "\\int_{0}^{2}f(x)dx=\\;\\color{#1E9E62}{-\\frac{16}{3}}", note: "积分"),
        .init(kind: .matrix, text: "A = \\begin{pmatrix}2 & 0 \\\\ 0 & 1\\end{pmatrix}", note: " A：看变换"),
        .init(kind: .shape, text: "正方形（边长 3）"),
    ], hasLooseInk: true)

    func testPromptListsEverythingInOrder() {
        let p = NoteSummarizer.prompt(digest, withImage: true)
        XCTAssertTrue(p.hasPrefix("草稿名：函数与导数"))
        XCTAssertTrue(p.contains("1. 函数：f\\left( x\\right) =x^{2}-4"))
        XCTAssertTrue(p.contains("3. 求解：\\int_{0}^{2}f(x)dx"))
        XCTAssertTrue(p.contains("（积分）"))
        XCTAssertTrue(p.contains("5. 图形：正方形（边长 3）"))
        XCTAssertTrue(p.hasSuffix("另附一张图：纸上没有收成式子的手写部分。"))
        XCTAssertFalse(NoteSummarizer.prompt(digest, withImage: false).contains("另附一张图"))
        XCTAssertTrue(NoteSummarizer.system.contains("JSON"))
        XCTAssertEqual(NoteSummarizer.model, "qwen3.8-max")
    }

    func testParseToleratesFencesAndChatter() throws {
        let reply = """
        好的，这是总结：
        ```json
        {"title": "二次函数求导", "points": ["f(x) = x² − 4 的导数是 2x", " ", "0 到 2 的积分是 −16/3"]}
        ```
        """
        let (title, points) = try NoteSummarizer.parse(reply)
        XCTAssertEqual(title, "二次函数求导")
        XCTAssertEqual(points, ["f(x) = x² − 4 的导数是 2x", "0 到 2 的积分是 −16/3"])
        XCTAssertThrowsError(try NoteSummarizer.parse("我不知道"))
        XCTAssertThrowsError(try NoteSummarizer.parse("{\"title\": \"空\", \"points\": []}"))
    }

    func testLocalSummaryFromFormulas() {
        let s = NoteSummarizer.local(digest, now: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(s.engine, "本地")
        XCTAssertTrue(s.isLocal)
        XCTAssertEqual(s.title, "函数与导数")
        XCTAssertEqual(s.points, [
            "写了函数 f(x) = x² − 4",
            "求导：f'(x) = 2x",
            "积分：∫₀²f(x)dx = −16/3",
            "矩阵 A：看变换",
            "画了正方形（边长 3）",
        ])
        let empty = NoteSummarizer.local(NoteDigest(title: "空白", lines: [], hasLooseInk: true))
        XCTAssertEqual(empty.points.count, 1)
        XCTAssertTrue(NoteDigest(title: "空白", lines: [], hasLooseInk: false).isEmpty)
    }

    func testPlainText() {
        XCTAssertEqual(NoteSummarizer.plain("\\lim_{x\\to\\infty}\\frac{1}{x}=0"), "lim(x→∞) 1/x = 0")
        XCTAssertEqual(NoteSummarizer.plain("\\sum_{k=1}^{n}k^2"), "∑(k = 1…n) k²")
        XCTAssertEqual(NoteSummarizer.plain("x^{-1}+3x^2-2"), "x⁻¹ + 3x² − 2")
    }
}
