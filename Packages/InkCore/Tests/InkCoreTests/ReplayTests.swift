import Foundation
import XCTest
@testable import InkCore

/// 黄金路径的合成笔迹：每个字符占一格，笔画数与 ReplayScript.golden 一致。
private enum Golden {
    enum Kind { case normal, superscript, minus, equals, prime }
    typealias Token = (strokes: Int, kind: Kind)

    /// f(x)=x^3-5x：16 笔
    static let act1: [Token] = [(2, .normal), (1, .normal), (2, .normal), (1, .normal), (2, .equals),
                                (2, .normal), (1, .superscript), (1, .minus), (2, .normal), (2, .normal)]
    /// f'(x)=3x^2-3x：17 笔
    static let act2: [Token] = [(2, .normal), (1, .prime), (1, .normal), (2, .normal), (1, .normal), (2, .equals),
                                (1, .normal), (2, .normal), (1, .superscript), (1, .minus), (1, .normal), (2, .normal)]

    /// 每个字符的笔画外框，按书写顺序。
    static func glyphs(_ tokens: [Token], x0: CGFloat, midY: CGFloat) -> [[CGRect]] {
        var x = x0
        return tokens.map { token in
            let w: CGFloat = token.kind == .superscript ? 14 : 22
            defer { x += w }
            return (0..<token.strokes).map { k -> CGRect in
                switch token.kind {
                case .normal:
                    let pw = (w - 4) / CGFloat(token.strokes)
                    return CGRect(x: x + 2 + CGFloat(k) * pw, y: midY - 15, width: pw, height: 30)
                case .superscript: return CGRect(x: x + 1, y: midY - 30, width: w - 2, height: 16)
                case .minus: return CGRect(x: x + 3, y: midY - 1.5, width: w - 6, height: 3)
                case .equals: return CGRect(x: x + 3, y: midY + (k == 0 ? -6.5 : 3.5), width: w - 6, height: 3)
                case .prime: return CGRect(x: x + 8, y: midY - 18, width: 4, height: 10)
                }
            }
        }
    }
}

/// 画布 + BandInkModel + 识别器：每加一笔、每擦一笔都可以「停一下」识别一次。
private final class Canvas {
    let ink = BandInkModel(mode: .function)
    var strokes: [InkStroke] = []
    var recognizer: InkRecognizer
    private var next = 1

    init(recognizer: InkRecognizer) {
        self.recognizer = recognizer
    }

    @discardableResult
    func add(_ rects: [CGRect]) -> [String] {
        rects.map { r in
            let id = "s\(next)"
            strokes.append(InkStroke(id: id, bounds: r, createdAt: Date(timeIntervalSince1970: Double(next))))
            next += 1
            return id
        }
    }

    func remove(_ ids: [String]) {
        strokes.removeAll { ids.contains($0.id) }
    }

    func clear() { strokes = [] }

    /// 这一刻停笔识别「最后改动的那一行」（按纵坐标找）。
    func pause(at midY: CGFloat) async throws -> String {
        let lines = ink.apply(strokes: strokes)
        let line = try XCTUnwrap(lines.first { !$0.strokes.isEmpty && $0.band.minY <= midY && $0.band.maxY >= midY })
        return try await recognizer.recognize(line: line, imagePNG: nil).latex
    }

    /// 一笔一笔写，每笔之后都停一下；返回每次识别的结果。
    func write(_ rects: [CGRect], midY: CGFloat) async throws -> [String] {
        var echoes: [String] = []
        for r in rects {
            add([r])
            echoes.append(try await pause(at: midY))
        }
        return echoes
    }
}

final class ReplayTests: XCTestCase {
    /// 旧的按顺序回放：写到一半多停一次就会把后面的行提前放出来。按笔画数取就不会。
    func testPausingAfterEveryStrokeNeverShiftsTheGoldenPath() async throws {
        let canvas = Canvas(recognizer: ReplayRecognizer())

        // 第一幕：写 f(x)=x^3-5x
        let line1 = Golden.glyphs(Golden.act1, x0: 40, midY: 150)
        let echoes1 = try await canvas.write(line1.flatMap { $0 }, midY: 150)
        XCTAssertEqual(echoes1.last, "f(x)=x^3-5x")
        XCTAssertEqual(echoes1.filter { $0 == "f(x)=x^3-5x" }.count, 1, "最后一笔落下之前不会给出整行")
        XCTAssertFalse(echoes1.contains("f(x)=x^3-3x"))

        // 擦掉 5（两笔，中间停一下），写 3
        let five = canvas.strokes.suffix(4).prefix(2).map(\.id)
        canvas.remove([five[0]])
        let afterFirstErase = try await canvas.pause(at: 150)
        canvas.remove([five[1]])
        let afterSecondErase = try await canvas.pause(at: 150)
        XCTAssertEqual([afterFirstErase, afterSecondErase], ["f(x)=x^3-x", "f(x)=x^3-x"], "连续的擦除算一轮")
        canvas.add([CGRect(x: 40 + 7 * 22 + 14 + 2, y: 135, width: 18, height: 30)])
        let fixed1 = try await canvas.pause(at: 150)
        XCTAssertEqual(fixed1, "f(x)=x^3-3x")

        // 第二幕：写到「3x^2 -」停一下，只有 1 项，不会提前批改
        canvas.ink.mode = .derivative
        let line2 = Golden.glyphs(Golden.act2, x0: 40, midY: 350)
        let throughMinus = try await canvas.write(line2[0...9].flatMap { $0 }, midY: 350)
        XCTAssertEqual(throughMinus.last, "f'(x)=3x^2")
        let rest = try await canvas.write(line2[10...].flatMap { $0 }, midY: 350)
        XCTAssertEqual(rest.last, "f'(x)=3x^2-3x")

        // 一口气擦掉 -3x 写 -3，中间没停
        let tail = canvas.strokes.suffix(4).map(\.id)
        canvas.remove(tail)
        canvas.add([CGRect(x: 40 + 8 * 22 + 14 + 3, y: 348.5, width: 16, height: 3),
                    CGRect(x: 40 + 9 * 22 + 14 + 2, y: 335, width: 18, height: 30)])
        let fixed2 = try await canvas.pause(at: 350)
        XCTAssertEqual(fixed2, "f'(x)=3x^2-3")
    }

    func testClearingTheCanvasAndRunningTheDemoAgainStillMatches() async throws {
        let tracker = ReplayTracker()
        let canvas = Canvas(recognizer: ReplayRecognizer(tracker: tracker))
        let line1 = Golden.glyphs(Golden.act1, x0: 40, midY: 150).flatMap { $0 }
        _ = try await canvas.write(line1, midY: 150)

        // 清屏重写：BandInkModel 的行号接着往上数（L2），没 reset 时按「函数第 2 行」找，退回第 1 行的录音
        canvas.clear()
        _ = canvas.ink.apply(strokes: [])
        let again = try await canvas.write(line1, midY: 150)
        XCTAssertEqual(again.last, "f(x)=x^3-5x")

        // reset 之后重新从第 1 行数
        canvas.clear()
        _ = canvas.ink.apply(strokes: [])
        tracker.reset()
        let third = try await canvas.write(line1, midY: 150)
        XCTAssertEqual(third.last, "f(x)=x^3-5x")
    }

    func testTrackerOrdinalsAndEraseRounds() {
        let t = ReplayTracker()
        XCTAssertEqual(t.observe(lineID: "L1", mode: .function, strokeIDs: ["a", "b", "c"]),
                       .init(mode: .function, ordinal: 1, erasePasses: 0, strokesInPass: 3))
        XCTAssertEqual(t.observe(lineID: "L2", mode: .derivative, strokeIDs: ["d"]).ordinal, 1, "按模式各自数")
        XCTAssertEqual(t.observe(lineID: "L3", mode: .derivative, strokeIDs: ["e"]).ordinal, 2)

        func pos(_ ids: [String]) -> [Int] {
            let p = t.observe(lineID: "L1", mode: .function, strokeIDs: ids)
            return [p.erasePasses, p.strokesInPass]
        }
        XCTAssertEqual(pos(["a", "b"]), [1, 0], "开始第 1 轮，还没写新的")
        XCTAssertEqual(pos(["a"]), [1, 0], "连续擦除是同一轮")
        XCTAssertEqual(pos(["a", "f"]), [1, 1], "写回来不算擦，新写 1 笔")
        XCTAssertEqual(pos(["a", "g"]), [2, 1], "擦了又写，没停顿：新的一轮，新写的 g 算进去")
        XCTAssertEqual(pos(["a", "g", "h"]), [2, 2])

        t.reset()
        XCTAssertEqual(t.observe(lineID: "L5", mode: .function, strokeIDs: ["x"]),
                       .init(mode: .function, ordinal: 1, erasePasses: 0, strokesInPass: 1))
    }

    func testScriptLookupRecordingAndJSONShape() throws {
        var s = ReplayScript()
        s.record(mode: .function, ordinal: 1, erasePasses: 0, strokesInPass: 5, latex: "f(x)")
        s.record(mode: .function, ordinal: 1, erasePasses: 0, strokesInPass: 5, latex: "f(x)=")
        s.record(mode: .function, ordinal: 1, erasePasses: 1, strokesInPass: 3, latex: "f")
        XCTAssertEqual(s.latex(mode: .function, ordinal: 1, erasePasses: 0, strokesInPass: 4), "", "还不够第一步")
        XCTAssertEqual(s.latex(mode: .function, ordinal: 1, erasePasses: 0, strokesInPass: 9), "f(x)=", "同一步只留最后一次")
        XCTAssertEqual(s.latex(mode: .function, ordinal: 1, erasePasses: 3, strokesInPass: 9), "f", "轮次取不超过的最后一段")
        XCTAssertNil(s.latex(mode: .derivative, ordinal: 1, erasePasses: 0, strokesInPass: 9), "这一模式没录过")

        let json = String(decoding: try JSONEncoder().encode(s), as: UTF8.self)
        XCTAssertTrue(json.contains("\"function\\/1\"") || json.contains("\"function/1\""))
        XCTAssertTrue(json.contains("\"min_strokes\""))
        XCTAssertTrue(json.contains("\"erase_passes\""))

        let merged = ReplayScript.golden.overlaid(with: s)
        XCTAssertEqual(merged.latex(mode: .function, ordinal: 1, erasePasses: 0, strokesInPass: 16), "f(x)=", "录过的行整行替换")
        XCTAssertEqual(merged.latex(mode: .derivative, ordinal: 1, erasePasses: 0, strokesInPass: 17), "f'(x)=3x^2-3x", "没录的行用内置的")
    }

    func testLiveResultsAreRecordedAndReplayedAtTheSameStrokeCounts() async throws {
        struct FakeLive: InkRecognizer {
            func recognize(line: InkLine, imagePNG: Data?) async throws -> RecognitionResult {
                let latex = line.strokes.count >= 3 ? "f(x)=x^2" : (line.strokes.count == 2 ? "" : "f")
                return RecognitionResult(lineID: line.id, revision: line.revision, latex: latex, engine: "fake")
            }
        }
        let file = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("replay-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }

        let tracker = ReplayTracker()
        let recorder = ReplayRecorder(fileURL: file)
        let live = Canvas(recognizer: TrackingRecognizer(FakeLive(), tracker: tracker, recorder: recorder))
        let rects = (0..<3).map { CGRect(x: 40 + CGFloat($0) * 22, y: 135, width: 18, height: 30) }
        let liveEchoes = try await live.write(rects, midY: 150)
        XCTAssertEqual(liveEchoes, ["f", "", "f(x)=x^2"])

        let reloaded = ReplayRecorder(fileURL: file).script
        XCTAssertEqual(reloaded.lines.keys.sorted(), ["function/1"])
        XCTAssertEqual(reloaded.lines["function/1"]?.first?.steps.map(\.minStrokes), [1, 3], "空结果不录")

        let replayed = Canvas(recognizer: ReplayRecognizer(script: reloaded))
        let replayEchoes = try await replayed.write(rects, midY: 150)
        XCTAssertEqual(replayEchoes, ["f", "f", "f(x)=x^2"])

        recorder.clear()
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }
}
