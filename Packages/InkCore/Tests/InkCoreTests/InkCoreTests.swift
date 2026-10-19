import Foundation
import XCTest
@testable import InkCore

private func stroke(_ id: String, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, t: Double = 0,
                    points: [CGPoint] = []) -> InkStroke {
    InkStroke(id: id, bounds: CGRect(x: x, y: y, width: w, height: h), createdAt: Date(timeIntervalSince1970: t), points: points)
}

/// 手动推进的假时钟。
final class FakeScheduler: GateScheduler {
    final class Job: GateCancellable {
        let at: TimeInterval
        let work: () -> Void
        var cancelled = false
        init(at: TimeInterval, work: @escaping () -> Void) { self.at = at; self.work = work }
        func cancel() { cancelled = true }
    }
    var now: TimeInterval = 0
    var jobs: [Job] = []
    func schedule(after seconds: TimeInterval, _ work: @escaping () -> Void) -> GateCancellable {
        let j = Job(at: now + seconds, work: work)
        jobs.append(j)
        return j
    }
    func advance(_ dt: TimeInterval) {
        now += dt
        while let j = jobs.filter({ !$0.cancelled && $0.at <= now }).min(by: { $0.at < $1.at }) {
            j.cancelled = true
            j.work()
        }
    }
}

final class InkModelTests: XCTestCase {
    func testBandsGroupSuperscriptsAndMinus() {
        let m = BandInkModel(mode: .function)
        // 第一行：f(x)=x 和一个上标 3（中心偏上），一条减号
        var s = [stroke("s1", 40, 100, 30, 40, t: 1), stroke("s2", 80, 90, 10, 14, t: 2), stroke("s3", 100, 120, 20, 3, t: 3)]
        var lines = m.apply(strokes: s)
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].id, "L1")
        XCTAssertEqual(lines[0].strokes.count, 3)
        XCTAssertEqual(lines[0].revision, 3)
        // 第二行：离得远，新建 L2
        s.append(stroke("s4", 40, 220, 30, 40, t: 4))
        lines = m.apply(strokes: s)
        XCTAssertEqual(lines.map(\.id), ["L1", "L2"])
        XCTAssertEqual(lines[0].revision, 3, "第一行没变，版本号不动")
    }

    func testEraseRecordsRemovedIDsAndBumpsRevision() {
        let m = BandInkModel(mode: .derivative)
        let a = stroke("s1", 40, 100, 30, 40, t: 1), b = stroke("s2", 80, 100, 30, 40, t: 2)
        _ = m.apply(strokes: [a, b])
        var lines = m.apply(strokes: [a])
        XCTAssertEqual(lines[0].removedStrokeIDs, ["s2"])
        XCTAssertEqual(lines[0].revision, 3)
        m.markSent(lineID: "L1")
        lines = m.apply(strokes: [a, stroke("s3", 80, 100, 20, 40, t: 3)])
        XCTAssertEqual(lines[0].removedStrokeIDs, [])
        XCTAssertEqual(lines[0].strokes.map(\.id), ["s1", "s3"])
        XCTAssertEqual(lines[0].revision, 4)
    }

    func testLineIDsNeverReused() {
        let m = BandInkModel()
        _ = m.apply(strokes: [stroke("s1", 40, 100, 30, 40, t: 1)])
        _ = m.apply(strokes: [])
        let lines = m.apply(strokes: [stroke("s2", 40, 400, 30, 40, t: 2)])
        XCTAssertEqual(lines.first { !$0.strokes.isEmpty }?.id, "L2")
    }

    func testGeometryIsOneLine() {
        let m = BandInkModel(mode: .geometry)
        let lines = m.apply(strokes: [stroke("s1", 40, 100, 300, 10, t: 1), stroke("s2", 40, 400, 30, 40, t: 2)])
        XCTAssertEqual(lines.map(\.id), ["G1"])
        XCTAssertEqual(lines[0].strokes.count, 2)
    }
}

final class CheckGateTests: XCTestCase {
    func line(_ rev: Int, mode: InkMode = .derivative) -> InkLine {
        InkLine(id: "L2", revision: rev, mode: mode, band: CGRect(x: 0, y: 0, width: 100, height: 40), strokes: [], removedStrokeIDs: [])
    }

    func makeGate(_ clock: FakeScheduler, log: @escaping (String) -> Void) -> CheckGate {
        let g = CheckGate(scheduler: clock)
        g.expectedTermCount = { _ in 2 }
        g.onRecognize = { l, t in log("recognize \(l.revision) \(t.rawValue)") }
        g.onCheck = { l, t in log("check \(l.revision) \(t.rawValue)") }
        g.onUnreadable = { l in log("unreadable \(l.revision)") }
        return g
    }

    func testHalfLineOnlyEchoes() {
        let clock = FakeScheduler(); var log: [String] = []
        let g = makeGate(clock) { log.append($0) }
        g.strokeChanged(line: line(1), at: Date())
        clock.advance(0.7)
        XCTAssertEqual(log, ["recognize 1 pause"])
        g.recognitionReturned(lineID: "L2", revision: 1, latex: "f'(x)=3x^2-", termCount: 1, parseable: true)
        clock.advance(1.0)
        XCTAssertEqual(log, ["recognize 1 pause"], "只有 1 项，不批改")
    }

    func testFinishedLineAutoChecksOnce() {
        let clock = FakeScheduler(); var log: [String] = []
        let g = makeGate(clock) { log.append($0) }
        g.strokeChanged(line: line(5), at: Date())
        clock.advance(0.7)
        g.recognitionReturned(lineID: "L2", revision: 5, latex: "f'(x)=3x^2-3x", termCount: 2, parseable: true)
        clock.advance(0.9)
        XCTAssertEqual(log, ["recognize 5 pause", "check 5 auto_check"])
        clock.advance(5)
        XCTAssertEqual(log.count, 2, "同一版本只批一次")
    }

    func testSlowRecognitionStillChecksWhenItArrives() {
        let clock = FakeScheduler(); var log: [String] = []
        let g = makeGate(clock) { log.append($0) }
        g.strokeChanged(line: line(2), at: Date())
        clock.advance(2)
        XCTAssertEqual(log, ["recognize 2 pause"])
        g.recognitionReturned(lineID: "L2", revision: 2, latex: "x", termCount: 2, parseable: true)
        XCTAssertEqual(log.last, "check 2 auto_check")
    }

    func testEraseResetsTimersAndDropsStaleResults() {
        let clock = FakeScheduler(); var log: [String] = []
        let g = makeGate(clock) { log.append($0) }
        g.strokeChanged(line: line(3), at: Date())
        clock.advance(1.0)
        g.strokeChanged(line: line(4), at: Date()) // 擦了一笔
        g.recognitionReturned(lineID: "L2", revision: 3, latex: "old", termCount: 2, parseable: true) // 过期
        clock.advance(1.0)
        XCTAssertEqual(log, ["recognize 3 pause", "recognize 4 pause"])
        XCTAssertFalse(g.hasRecognition(lineID: "L2"))
    }

    func testDoubleTapForcesCheckEvenWithOneTerm() {
        let clock = FakeScheduler(); var log: [String] = []
        let g = makeGate(clock) { log.append($0) }
        g.strokeChanged(line: line(1), at: Date())
        clock.advance(0.7)
        g.recognitionReturned(lineID: "L2", revision: 1, latex: "f'(x)=3x^2", termCount: 1, parseable: true)
        g.doubleTapped(lineID: "L2")
        XCTAssertEqual(log.last, "check 1 double_tap")
    }

    func testDoubleTapBeforeRecognitionWaitsThenChecks() {
        let clock = FakeScheduler(); var log: [String] = []
        let g = makeGate(clock) { log.append($0) }
        g.strokeChanged(line: line(1), at: Date())
        g.doubleTapped(lineID: "L2")
        XCTAssertEqual(log, ["recognize 1 double_tap"])
        clock.advance(3)
        XCTAssertEqual(log.count, 1, "双击取消了计时")
        g.recognitionReturned(lineID: "L2", revision: 1, latex: "???", termCount: 0, parseable: false)
        XCTAssertEqual(log.last, "unreadable 1")
    }

    func testFunctionModeNeverChecks() {
        let clock = FakeScheduler(); var log: [String] = []
        let g = makeGate(clock) { log.append($0) }
        g.strokeChanged(line: line(1, mode: .function), at: Date())
        clock.advance(0.7)
        g.recognitionReturned(lineID: "L2", revision: 1, latex: "f(x)=x^3-3x", termCount: 2, parseable: true)
        clock.advance(3)
        g.doubleTapped(lineID: "L2")
        XCTAssertEqual(log, ["recognize 1 pause", "recognize 1 double_tap"])
    }
}

final class LatexTermsTests: XCTestCase {
    func testGoldenLines() {
        let f = LatexTerms.parse("f(x) = x^{3} - 3x")
        XCTAssertEqual(f.kind, .function)
        XCTAssertEqual(f.terms?.map(\.pow), [3, 1])
        XCTAssertEqual(f.terms?.map(\.coef), [1, -3])
        let d = LatexTerms.parse("f^{\\prime}(x)=3x^2-3x")
        XCTAssertEqual(d.kind, .derivative)
        XCTAssertEqual(d.terms?.map(\.latex), ["3x^2", "-3x"])
        XCTAssertEqual(d.termCount, 2)
        XCTAssertTrue(d.parseable)
    }

    func testHalfWrittenAndOddForms() {
        XCTAssertEqual(LatexTerms.parse("f'(x)=3x^2-").termCount, 1)
        XCTAssertEqual(LatexTerms.parse("f(x)=\\frac{1}{2}x^2").terms?.first?.coef, 0.5)
        XCTAssertEqual(LatexTerms.parse("3x^2\\cdot 2").terms?.first?.coef, 6)
        XCTAssertEqual(LatexTerms.parse("f'(x)=0").terms?.first?.pow, 0)
        XCTAssertFalse(LatexTerms.parse("\\int x^2 dx").parseable)
        XCTAssertEqual(LatexTerms.parse("f(x)=-x^3+6x").terms?.map(\.coef), [-1, 6])
    }
}

final class TermSegmenterTests: XCTestCase {
    /// f'(x)=3x²-3x 的大致笔画外框（单位 pt）
    func testGoldenDerivativeLine() {
        let row: [InkStroke] = [
            stroke("f", 10, 100, 20, 60), stroke("'", 32, 98, 4, 10), stroke("(", 40, 100, 10, 50), stroke("x1", 52, 115, 18, 30),
            stroke(")", 72, 100, 10, 50), stroke("=a", 90, 120, 26, 2), stroke("=b", 90, 132, 26, 2),
            stroke("3", 125, 105, 22, 40), stroke("x2", 150, 115, 22, 30), stroke("x2'", 150, 115, 22, 30), stroke("2", 175, 95, 12, 18),
            stroke("-", 196, 126, 20, 2),
            stroke("3b", 222, 105, 22, 40), stroke("x3", 248, 115, 22, 30), stroke("x3'", 248, 115, 22, 30),
        ]
        let boxes = TermSegmenter.termBoxes(strokes: row, expectedCount: 2)
        XCTAssertEqual(boxes?.count, 2)
        XCTAssertEqual(boxes?[1].minX, 196)
        XCTAssertEqual(boxes?[1].maxX, 270)
        XCTAssertNil(TermSegmenter.termBoxes(strokes: row, expectedCount: 3), "项数对不上就退回圈整行")
    }
}

final class GeometryTests: XCTestCase {
    private func line(_ a: CGPoint, _ b: CGPoint, n: Int = 20) -> [CGPoint] {
        (0...n).map { i in
            let t = CGFloat(i) / CGFloat(n)
            return CGPoint(x: a.x + (b.x - a.x) * t + CGFloat(i % 3) * 0.6, y: a.y + (b.y - a.y) * t)
        }
    }

    private func s(_ id: String, _ pts: [CGPoint], _ t: Double) -> InkStroke {
        let xs = pts.map(\.x), ys = pts.map(\.y)
        return InkStroke(id: id, bounds: CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!),
                         createdAt: Date(timeIntervalSince1970: t), points: pts)
    }

    func testTriangleWithOneMedian() throws {
        let A = CGPoint(x: 200, y: 60), B = CGPoint(x: 60, y: 300), C = CGPoint(x: 360, y: 290)
        let M = CGPoint(x: (B.x + C.x) / 2 + 6, y: (B.y + C.y) / 2 - 3)
        let strokes = [s("1", line(A, B), 1), s("2", line(B, C), 2), s("3", line(C, A), 3), s("4", line(A, M), 4)]
        let g = try XCTUnwrap(GeometrySketchRecognizer.recognize(strokes: strokes))
        XCTAssertEqual(g.points.filter { $0.role == "free" }.map(\.id), ["A", "B", "C"])
        XCTAssertEqual(g.relations, [GeometrySketch.Relation(type: "midpoint", of: ["B", "C"], point: "M")])
        XCTAssertTrue(g.objects.contains { $0.id == "median_A" && $0.points == ["A", "M"] })
        let a = try XCTUnwrap(g.points.first { $0.id == "A" })
        XCTAssertEqual(a.x, 200, accuracy: 6)
        XCTAssertEqual(a.y, 60, accuracy: 6)
    }

    func testClosedSingleStrokeTriangleAndThreeMedians() throws {
        let A = CGPoint(x: 200, y: 60), B = CGPoint(x: 60, y: 300), C = CGPoint(x: 360, y: 290)
        let tri = line(A, B) + line(B, C) + line(C, A)
        func mid(_ p: CGPoint, _ q: CGPoint) -> CGPoint { CGPoint(x: (p.x + q.x) / 2, y: (p.y + q.y) / 2) }
        let strokes = [s("t", tri, 1), s("ma", line(A, mid(B, C)), 2), s("mb", line(B, mid(C, A)), 3), s("mc", line(C, mid(A, B)), 4)]
        let g = try XCTUnwrap(GeometrySketchRecognizer.recognize(strokes: strokes))
        XCTAssertEqual(g.relations.count, 3)
        XCTAssertEqual(Set(g.relations.map { $0.of.sorted() }), [["B", "C"], ["A", "C"], ["A", "B"]])
    }

    func testScribbleIsRejected() {
        let pts = (0..<40).map { CGPoint(x: CGFloat($0 % 2) * 30 + 100, y: CGFloat($0) * 2 + 100) }
        XCTAssertNil(GeometrySketchRecognizer.recognize(strokes: [s("z", pts, 1)]))
    }
}

final class ContractsTests: XCTestCase {
    private func sample(_ name: String) throws -> Data {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try Data(contentsOf: root.appendingPathComponent("contracts/\(name)"))
    }

    func testUploadSampleRoundTrips() throws {
        let u = try JSONDecoder().decode(UploadRequest.self, from: sample("upload.sample.json"))
        XCTAssertEqual(u.lineID, "L2")
        XCTAssertEqual(u.trigger, .autoCheck)
        XCTAssertEqual(u.removedStrokeIDs, ["s12", "s13"])
        XCTAssertEqual(u.context?.functionLatex, "x^3-3x")
        let again = try JSONDecoder().decode(UploadRequest.self, from: JSONEncoder().encode(u))
        XCTAssertEqual(again, u)
    }

    func testAnnotationSampleAndRedaction() throws {
        let a = try JSONDecoder().decode(Annotation.self, from: sample("annotation.sample.json"))
        XCTAssertEqual(a.errors.first?.expectedLatex, "-3")
        XCTAssertEqual(a.errors.first?.rect, CGRect(x: 318, y: 336, width: 54, height: 44))
        let s = a.redactedForSocratic()
        XCTAssertNil(s.errors.first?.expectedLatex)
        XCTAssertNil(s.explanation)
    }

    func testGeometrySampleDecodesAsSketch() throws {
        let g = try JSONDecoder().decode(GeometrySketch.self, from: sample("scene-geometry.sample.json"))
        XCTAssertEqual(g.relations.first?.point, "M")
    }
}

final class ExplanationTests: XCTestCase {
    func testTemplates() {
        XCTAssertEqual(Explanation.derivative(coef: -3, pow: 1), "x 求导得 1，所以 −3x 求导后是 −3。")
        XCTAssertEqual(Explanation.derivative(coef: 1, pow: 3), "x³ 求导得 3x²，所以 x³ 求导后是 3x²。")
        XCTAssertEqual(Explanation.derivative(coef: 5, pow: 0), "常数求导得 0，所以 5 求导后是 0。")
        XCTAssertEqual(Explanation.pretty("-3x^2"), "−3x²")
    }

    func testModelReplyParsing() throws {
        XCTAssertEqual(try extractLatex(fromModelReply: "```json\n{\"latex\": \"f'(x)=3x^2-3x\"}\n```"), "f'(x)=3x^2-3x")
        XCTAssertThrowsError(try extractLatex(fromModelReply: "sorry"))
    }
}

final class DerivativeCheckTests: XCTestCase {
    func testGoldenWrongLine() throws {
        let r = try XCTUnwrap(DerivativeCheck.check(functionLatex: "f(x)=x^3-3x", derivativeLatex: "f'(x)=3x^2-3x"))
        XCTAssertFalse(r.ok)
        XCTAssertEqual(r.findings.count, 1)
        XCTAssertEqual(r.findings[0].termIndex, 1)
        XCTAssertEqual(r.findings[0].kind, "not_differentiated")
        XCTAssertEqual(r.findings[0].wrongLatex, "-3x")
        XCTAssertEqual(r.findings[0].expectedLatex, "-3")
        XCTAssertEqual(r.explanation, "x 求导得 1，所以 −3x 求导后是 −3。")
        XCTAssertEqual(DerivativeCheck.expectedTermCount(functionLatex: "f(x)=x^3-3x"), 2)
    }

    func testGoldenFixedLineAndOrderFree() throws {
        XCTAssertEqual(DerivativeCheck.check(functionLatex: "f(x)=x^{3}-3x", derivativeLatex: "f^{\\prime}(x)=3x^{2}-3")?.ok, true)
        XCTAssertEqual(DerivativeCheck.check(functionLatex: "f(x)=x^3-3x", derivativeLatex: "f'(x)=-3+3x^2")?.ok, true)
    }

    func testOtherMistakes() throws {
        let a = try XCTUnwrap(DerivativeCheck.check(functionLatex: "f(x)=x^3-3x", derivativeLatex: "f'(x)=x^2-3"))
        XCTAssertEqual([a.findings[0].kind, a.findings[0].expectedLatex], ["wrong_coef", "3x^2"])
        let b = try XCTUnwrap(DerivativeCheck.check(functionLatex: "f(x)=x^2+5", derivativeLatex: "f'(x)=2x+5"))
        XCTAssertEqual([b.findings[0].kind, b.findings[0].expectedLatex], ["not_differentiated", "0"])
        XCTAssertEqual(b.explanation, "常数求导得 0，所以 5 求导后是 0。")
        let c = try XCTUnwrap(DerivativeCheck.check(functionLatex: "f(x)=x^3-3x+5", derivativeLatex: "f'(x)=3x^2"))
        XCTAssertEqual([c.findings[0].kind, c.findings[0].expectedLatex], ["missing_term", "-3"])
        XCTAssertNil(DerivativeCheck.check(functionLatex: "f(x)=x^3-3x", derivativeLatex: "\\int x"))
    }

    func testAnnotationCirclesTheWrongTermStrokes() throws {
        let rows: [(String, CGFloat, CGFloat, CGFloat, CGFloat)] = [
            ("f", 10, 100, 20, 60), ("(", 40, 100, 10, 50), ("x1", 52, 115, 18, 30), (")", 72, 100, 10, 50),
            ("=a", 90, 120, 26, 2), ("=b", 90, 132, 26, 2), ("3", 125, 105, 22, 40), ("x2", 150, 115, 22, 30),
            ("2", 175, 95, 12, 18), ("-", 196, 126, 20, 2), ("3b", 222, 105, 22, 40), ("x3", 248, 115, 22, 30),
        ]
        let strokes = rows.map { InkStroke(id: $0.0, bounds: CGRect(x: $0.1, y: $0.2, width: $0.3, height: $0.4), createdAt: Date()) }
        let line = InkLine(id: "L2", revision: 7, mode: .derivative, band: CGRect(x: 10, y: 95, width: 260, height: 65),
                           strokes: strokes, removedStrokeIDs: [])
        let a = try XCTUnwrap(DerivativeCheck.annotation(line: line, functionLatex: "f(x)=x^3-3x", derivativeLatex: "f'(x)=3x^2-3x"))
        XCTAssertEqual(a.revision, 7)
        XCTAssertEqual(a.errors.first?.bbox, [196, 105, 270, 145])
        XCTAssertEqual(a.errors.first?.expectedLatex, "-3")
        let s = try XCTUnwrap(DerivativeCheck.annotation(line: line, functionLatex: "f(x)=x^3-3x", derivativeLatex: "f'(x)=3x^2-3x", mode: .socratic))
        XCTAssertNil(s.errors.first?.expectedLatex)
        XCTAssertNil(s.explanation)
    }
}
