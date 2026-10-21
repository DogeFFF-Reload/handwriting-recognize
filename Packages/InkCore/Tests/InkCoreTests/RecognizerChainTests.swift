import Foundation
import XCTest
@testable import InkCore

private let line = InkLine(id: "F1", revision: 1, mode: .function, band: .zero, strokes: [], removedStrokeIDs: [])

/// 给定结果的识别器；latex 为 nil 时像断网一样抛错。
private struct Fixed: InkRecognizer {
    var latex: String?
    var engine: String

    func recognize(line: InkLine, imagePNG: Data?) async throws -> RecognitionResult {
        guard let latex else { throw RecognizerError.http(0, "断网") }
        return RecognitionResult(lineID: line.id, revision: line.revision, latex: latex, engine: engine)
    }
}

/// 像卡在 waitForIdle 的 SDK 调用：不理会取消，过 `seconds` 秒才回来。
private struct Stuck: InkRecognizer {
    var seconds: Double = 3

    func recognize(line: InkLine, imagePNG: Data?) async throws -> RecognitionResult {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { c.resume() }
        }
        return RecognitionResult(lineID: line.id, revision: line.revision, latex: "太晚了", engine: "stuck")
    }
}

private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var raised = false
    var value: Bool { lock.lock(); defer { lock.unlock() }; return raised }
    func raise() { lock.lock(); raised = true; lock.unlock() }
}

final class RecognizerChainTests: XCTestCase {
    func testErrorsAndEmptyResultsFallThroughToTheNextEngine() async throws {
        let chain = FallbackRecognizer([Fixed(latex: nil, engine: "MyScript"), Fixed(latex: "", engine: "百炼"),
                                        Fixed(latex: "f(x)=x^2", engine: "Server")])
        let r = try await chain.recognize(line: line, imagePNG: nil)
        XCTAssertEqual([r.latex, r.engine], ["f(x)=x^2", "Server"])
    }

    func testLastEngineEmptyResultIsReturnedAndAllFailingThrows() async throws {
        let empty = try await FallbackRecognizer([Fixed(latex: nil, engine: "a"), Fixed(latex: "", engine: "b")])
            .recognize(line: line, imagePNG: nil)
        XCTAssertEqual([empty.latex, empty.engine], ["", "b"], "最后一个的空结果照样返回，界面说「没认出来」")

        do {
            _ = try await FallbackRecognizer([Fixed(latex: nil, engine: "a")]).recognize(line: line, imagePNG: nil)
            XCTFail("都失败时应该抛错")
        } catch {
            XCTAssertEqual(error as? RecognizerError, .http(0, "断网"))
        }
    }

    /// MyScript 卡住（不理会取消）时，不等它，按时落到下一个引擎。
    func testStuckEngineFallsThroughAfterTheTimeout() async throws {
        let t0 = Date()
        let r = try await FallbackRecognizer([Stuck(), Fixed(latex: "f(x)=x", engine: "百炼")], timeout: 0.2)
            .recognize(line: line, imagePNG: nil)
        XCTAssertEqual(r.engine, "百炼")
        XCTAssertLessThan(Date().timeIntervalSince(t0), 2, "不该等卡住的那个 3 秒")
    }

    func testStuckLastEngineReportsTheTimeout() async throws {
        let t0 = Date()
        do {
            _ = try await FallbackRecognizer([Stuck()], timeout: 0.2).recognize(line: line, imagePNG: nil)
            XCTFail("应该超时")
        } catch {
            XCTAssertEqual(error as? DeadlineExceeded, DeadlineExceeded(seconds: 0.2))
        }
        XCTAssertLessThan(Date().timeIntervalSince(t0), 2)
    }

    func testNoTimeoutWaitsForTheEngine() async throws {
        let r = try await FallbackRecognizer([Stuck(seconds: 0.3)], timeout: nil).recognize(line: line, imagePNG: nil)
        XCTAssertEqual(r.latex, "太晚了")
    }

    func testDeadlinePassesResultsAndErrorsThrough() async throws {
        let v = try await withDeadline(seconds: 5) { 42 }
        XCTAssertEqual(v, 42)
        do {
            _ = try await withDeadline(seconds: 5) { () async throws -> Int in throw RecognizerError.noImage }
            XCTFail("应该把错原样抛出来")
        } catch {
            XCTAssertEqual(error as? RecognizerError, .noImage)
        }
    }

    func testDeadlineCancelsTheOperationWhenItExpires() async throws {
        let cancelled = Flag()
        _ = try? await withDeadline(seconds: 0.1) { () async -> Int in
            do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch { cancelled.raise() }
            return 0
        }
        for _ in 0..<100 where !cancelled.value { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertTrue(cancelled.value, "超时后 URLSession 这类请求应该被取消，不在后台接着跑")
    }

    func testCancellingTheCallerStopsWaiting() async throws {
        let t0 = Date()
        let task = Task { try await withDeadline(seconds: 10) { try await Stuck().recognize(line: line, imagePNG: nil) } }
        try await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()
        let outcome = await task.result
        XCTAssertThrowsError(try outcome.get()) { XCTAssertTrue($0 is CancellationError) }
        XCTAssertLessThan(Date().timeIntervalSince(t0), 2)
    }
}
