import Foundation
import XCTest
@testable import InkTutorServer

struct FakeModel: ModelClient {
    let replies: [String]
    final class Counter: @unchecked Sendable { var n = 0 }
    let counter = Counter()

    func chat(model: String, system: String?, prompt: String, imagePNGBase64: String?,
              maxTokens: Int, temperature: Double) async throws -> String {
        defer { counter.n += 1 }
        return replies[min(counter.n, replies.count - 1)]
    }
}

final class HintsTests: XCTestCase {
    let golden = HintRequest(kind: "not_differentiated", wrongLatex: "-3x", expectedLatex: "-3", sourceLatex: "-3x",
                             functionLatex: "x^3-3x", studentLine: "f'(x)=3x^2-3x", feedbackMode: "socratic",
                             level: 1, explanation: nil)

    func testLeakOnlyCatchesStandaloneAnswer() {
        XCTAssertTrue(Hints.leaks("−3x 求导后还剩 −3 吗？", secrets: ["-3"]))
        XCTAssertFalse(Hints.leaks("−3x 这一项求导后还剩什么？", secrets: ["-3"]), "学生写的 -3x 不算泄题")
        XCTAssertTrue(Hints.leaks("常数求导是零吗", secrets: ["0"]))
        XCTAssertTrue(Hints.leaks("应该是 3x²−3 吧", secrets: ["3x^2-3"]))
        XCTAssertFalse(Hints.leaks("x³ 求导时指数怎么变？", secrets: ["3x^2"]))
    }

    func testSocraticRetriesThenFallsBack() async {
        let leaky = FakeModel(replies: ["答案是 −3 哦", "就是 −3"])
        let r = await Hints.generate(golden, model: leaky)
        XCTAssertEqual(r.source, "fallback")
        XCTAssertEqual(r.text, "−3x 这一项，求导之后还剩下什么？")
        XCTAssertEqual(leaky.counter.n, 2)
    }

    func testSocraticAcceptsGoodQuestion() async {
        let r = await Hints.generate(golden, model: FakeModel(replies: ["“看看 −3x，求导后 x 还在吗？”"]))
        XCTAssertEqual(r.text, "看看 −3x，求导后 x 还在吗？")
        XCTAssertEqual(r.source, "model")
    }

    func testDirectModeKeepsAnswerAndPromptHasIt() async {
        var d = golden
        d.feedbackMode = "direct"
        d.explanation = "x 求导得 1，所以 −3x 求导后是 −3。"
        XCTAssertTrue(Hints.prompt(d).contains("这一项的正确结果：-3"))
        let r = await Hints.generate(d, model: FakeModel(replies: ["−3x 里的 x 求导变成 1，所以结果是 −3。"]))
        XCTAssertEqual(r.source, "model")
        XCTAssertEqual(Hints.fallback(d), "x 求导得 1，所以 −3x 求导后是 −3。")
    }

    func testReplaySequenceAndFallback() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("replay-\(UUID().uuidString)")
        let rec = ReplayStore(mode: .record, directory: dir)
        _ = try await withReplayFallback(store: rec, route: "recognize") { "f(x)=x^3-5x" }
        _ = try await withReplayFallback(store: rec, route: "recognize") { "f(x)=x^3-3x" }
        let play = ReplayStore(mode: .play, directory: dir)
        let a = try await withReplayFallback(store: play, route: "recognize") { XCTFail("play 不联网"); return "" }
        let b = try await withReplayFallback(store: play, route: "recognize") { "" }
        XCTAssertEqual([a.0, b.0], ["f(x)=x^3-5x", "f(x)=x^3-3x"])
        XCTAssertTrue(a.1)

        let fb = ReplayStore(mode: .fallback, directory: dir)
        let slow = try await withReplayFallback(store: fb, route: "recognize", timeout: 0.2) {
            try await Task.sleep(nanoseconds: 2_000_000_000)
            return "too late"
        }
        XCTAssertEqual(slow.0, "f(x)=x^3-5x")
        XCTAssertTrue(slow.1)
    }
}
