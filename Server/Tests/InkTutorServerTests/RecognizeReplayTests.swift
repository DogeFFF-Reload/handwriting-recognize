import Foundation
import InkCore
import XCTest
@testable import InkTutorServer

final class RecognizeReplayTests: XCTestCase {
    private func tempDir() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("replay-\(UUID().uuidString)")
    }

    private func upload(_ lineID: String, _ mode: InkMode, _ ids: [String]) -> UploadRequest {
        UploadRequest(mode: mode, lineID: lineID, revision: ids.count, trigger: .pause, region: Region(.zero),
                      strokes: ids.map { UploadStroke(id: $0, points: []) }, removedStrokeIDs: [])
    }

    /// 旧的 /recognize 回放按调用顺序放，写到一半多停一次就错位；现在按这一行的状态取。
    func testPlayFollowsTheLineNotTheCallOrder() async throws {
        let replay = RecognizeReplay(mode: .play, directory: tempDir())
        let ids = (1...16).map { "s\($0)" }
        func play(_ strokes: [String]) async throws -> String {
            try await recognizeWithReplay(replay, upload: upload("L1", .function, strokes)) {
                XCTFail("play 不联网")
                return ""
            }.0
        }
        let partial = try await play(Array(ids.prefix(5)))
        let more = try await play(Array(ids.prefix(11)))
        let full = try await play(ids)
        XCTAssertEqual([partial, more, full], ["f", "f(x)=x^3", "f(x)=x^3-5x"])

        // 擦掉 5（s13、s14，中间停一下），写 3
        let half = try await play(ids.filter { $0 != "s13" })
        let fixed = try await play(ids.filter { $0 != "s13" && $0 != "s14" } + ["s17"])
        XCTAssertEqual([half, fixed], ["f(x)=x^3-x", "f(x)=x^3-3x"])
    }

    /// App 双击确认后才识别（trigger = double_tap）：写法和估的笔数不同，也放整行。
    func testDoubleTapPlaysTheWholeLine() async throws {
        let replay = RecognizeReplay(mode: .play, directory: tempDir())
        var up = upload("F1", .function, (1...12).map { "s\($0)" })
        up.trigger = .doubleTap
        let r = try await recognizeWithReplay(replay, upload: up) {
            XCTFail("play 不联网")
            return ""
        }.0
        XCTAssertEqual(r, "f(x)=x^3-5x")
    }

    func testRecordedResultsReplaceTheBuiltInLine() async throws {
        let dir = tempDir()
        let rec = RecognizeReplay(mode: .record, directory: dir)
        let r = try await recognizeWithReplay(rec, upload: upload("L1", .function, ["a", "b", "c"])) { "f(x)=x^2" }
        XCTAssertEqual(r.0, "f(x)=x^2")
        XCTAssertFalse(r.1)

        let play = RecognizeReplay(mode: .play, directory: dir)
        let replayed = try await recognizeWithReplay(play, upload: upload("L7", .function, ["x", "y", "z"])) { "" }
        XCTAssertEqual(replayed.0, "f(x)=x^2", "按「函数第 1 行、第 0 轮、3 笔」取，跟行号 L7 无关")
        let derivative = try await recognizeWithReplay(play, upload: upload("L8", .derivative, (1...17).map { "d\($0)" })) { "" }
        XCTAssertEqual(derivative.0, "f'(x)=3x^2-3x", "没录过的推导行用内置的黄金路径")
    }

    func testFallbackUsesTheKeyedReplayWhenTheModelIsSlow() async throws {
        let replay = RecognizeReplay(mode: .fallback, directory: tempDir())
        let slow = try await recognizeWithReplay(replay, upload: upload("L2", .derivative, (1...14).map { "d\($0)" }),
                                                 timeout: 0.2) {
            try await Task.sleep(nanoseconds: 2_000_000_000)
            return "too late"
        }
        XCTAssertEqual(slow.0, "f'(x)=3x^2", "写到 3x^2- 时只有 1 项，不会提前批改")
        XCTAssertTrue(slow.1)
    }
}
