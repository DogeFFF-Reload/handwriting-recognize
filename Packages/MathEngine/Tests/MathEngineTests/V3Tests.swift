//
//  V3Tests.swift
//  MathEngine
//
//  v3 的验收测试：direct 模式（PDF D5）、CheckGate 就绪判断（D1）、
//  滑条重算、切线、错项框、以及"任何垃圾输入都不许让 App 闪退"。
//
//  Mac / Linux 都用 `swift test` 跑。
//

import Foundation
import XCTest
@testable import MathEngine

final class V3Tests: XCTestCase {

    // MARK: - 夹具

    func load(_ name: String, subdirectory: String? = nil) throws -> Data {
        let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: subdirectory)
            ?? Bundle.module.url(forResource: name, withExtension: "json")
        guard let found = url else { throw XCTSkip("缺少夹具 \(name).json") }
        return try Data(contentsOf: found)
    }

    func resourceDir() -> URL? {
        Bundle.module.resourceURL
    }

    // MARK: - 与 Python 参考实现对账

    func testParityWithPythonReference() throws {
        let data = try load("parity_cases", subdirectory: "contracts")
        let report = try Parity.run(data)
        XCTAssertEqual(report.failures, 0, "\n" + report.text)
        XCTAssertGreaterThan(report.total, 10, "对账条数太少")
    }

    // MARK: - D5：direct 模式下发正确项 + 一句说明

    func testDirectModeGivesAnswerAndExplanation() {
        let req = CheckRequest(mode: "derivative",
                               lines: [.init(id: "L2", latex: "f'(x)=3x^2-3x", bbox: Box(x: 40, y: 320, w: 600, h: 60))],
                               context: .init(functionLatex: "x^3-3x"),
                               feedbackMode: .direct)
        let a = MathEngineAPI.check(req)
        XCTAssertFalse(a.ok)
        XCTAssertEqual(a.feedbackMode, "direct")
        XCTAssertEqual(a.errors.count, 1)
        let e = a.errors[0]
        XCTAssertEqual(e.kind, "wrong_term")
        XCTAssertEqual(e.wrongLatex, "-3x")
        XCTAssertEqual(e.expectedLatex, "-3", "direct 模式必须下发正确项")
        XCTAssertEqual(e.charSpan, [4, 7])
        XCTAssertEqual(e.bboxSource, "term", "有字符区间时应圈到那一项，不是整行")
        let x = try? XCTUnwrap(e.explanation)
        XCTAssertTrue(x?.contains("−3") ?? false, "说明里应有正确项：\(x ?? "nil")")
        XCTAssertTrue(x?.contains("求导") ?? false, "说明应是套模板的推导：\(x ?? "nil")")
        XCTAssertEqual(a.checked.rhsLatex, ["3x^2-3x"], "char_span 相对归一化后的正文")
    }

    func testSocraticModeNeverLeaksAnswer() {
        let req = CheckRequest(mode: "derivative",
                               lines: [.init(id: "L2", latex: "f'(x)=3x^2-3x")],
                               context: .init(functionLatex: "x^3-3x"),
                               feedbackMode: .socratic)
        let a = MathEngineAPI.check(req)
        XCTAssertEqual(a.feedbackMode, "socratic")
        XCTAssertEqual(a.errors.count, 1)
        let e = a.errors[0]
        XCTAssertNil(e.expectedLatex, "socratic 模式不许下发正确项")
        XCTAssertNil(e.explanation, "socratic 模式不下发说明，改走反问流")
        // 学生自己写的 -3x 里就含 -3，先把它抹掉再看（PDF 里提醒过这一点）
        let stripped = e.hintFallback.replacingOccurrences(of: "-3x", with: "")
        XCTAssertFalse(stripped.contains("−3"), "兜底反问不许泄题：\(e.hintFallback)")
        XCTAssertFalse(stripped.contains("-3"))
    }

    func testMissingTermCirclesWholeLine() {
        let a = MathEngineAPI.check(CheckRequest(
            mode: "derivative",
            lines: [.init(id: "L2", latex: "f'(x)=3x^2", bbox: Box(x: 40, y: 320, w: 600, h: 60))],
            context: .init(functionLatex: "x^3-3x")))
        XCTAssertEqual(a.errors.count, 1)
        XCTAssertEqual(a.errors[0].kind, "missing_term")
        XCTAssertEqual(a.errors[0].bboxSource, "line", "没有字符区间的错误圈整行")
        XCTAssertEqual(a.errors[0].bbox, Box(x: 40, y: 320, w: 600, h: 60))
    }

    func testMultiLineKeepsLineIds() {
        let a = MathEngineAPI.check(CheckRequest(
            mode: "derivative",
            lines: [.init(id: "L1", latex: "f'(x)=3x^2-3", revision: 2),
                    .init(id: "L2", latex: "f'(x)=3x^2-3x", revision: 4)],
            context: .init(functionLatex: "x^3-3x")))
        XCTAssertFalse(a.ok)
        XCTAssertEqual(a.errors.count, 1)
        XCTAssertEqual(a.errors[0].lineId, "L2")
        XCTAssertEqual(a.checked.lineCount, 2)
    }

    func testMaxErrorsDegrades() {
        let a = MathEngineAPI.check(CheckRequest(
            mode: "derivative",
            lines: [.init(id: "L", latex: "f'(x)=3x^2-3x+1")],
            context: .init(functionLatex: "x^3-3x"),
            options: .init(withScene: true, maxErrors: 1)))
        XCTAssertEqual(a.errors.count, 1)
        XCTAssertTrue(a.degraded.contains("errors_truncated"))
    }

    // MARK: - D1：CheckGate 就绪判断

    func testReadinessHalfLineIsIncomplete() {
        // 「写到 3x^2-3 时只有 2 项」——PDF 的例子，正确导数有 2 项，所以它其实够了；
        // 真正拦得住的是「写到 3x^2-1 才 1 项」和「f'(x)= 什么都没写」
        XCTAssertEqual(CheckGateSupport.derivative(functionLatex: "x^3-3x", lineLatex: "f'(x)=3x^2"),
                       .incomplete(have: 1, want: 2))
        XCTAssertEqual(CheckGateSupport.derivative(functionLatex: "x^3-3x", lineLatex: "f'(x)=3x^2-3x"),
                       .ready)
        if case .unparsable = CheckGateSupport.derivative(functionLatex: "x^3-3x", lineLatex: "f'(x)=") {
            // ok
        } else {
            XCTFail("空正文应判 unparsable")
        }
    }

    func testReadinessFunctionMode() {
        XCTAssertEqual(CheckGateSupport.function(latex: "f(x)=x^3-5x"), .ready)
        XCTAssertEqual(CheckGateSupport.function(latex: "f(x)="), .unparsable("读不出可画的函数"))
    }

    func testReadinessMatrixAndIntegral() {
        XCTAssertEqual(CheckGateSupport.matrix(latex: "\\begin{pmatrix}1&2\\\\3&4\\end{pmatrix}"),
                       .incomplete(have: 1, want: 3))
        XCTAssertEqual(CheckGateSupport.integral(latex: "\\int 2x\\,dx = x^2+C"), .ready)
    }

    // MARK: - 滑条重算（P2 在 App 里直接调）

    func testSliderDragRecomputesCurve() throws {
        let scene = try FunctionSceneBuilder.build("f(x)=x^3-5x")
        XCTAssertEqual(scene.paramName(forPow: 1), "b", "terms 里每一项都要显式绑定到滑条名")

        // 第一幕：把 5 改成 3 → 图像变形，极值点跟着变
        let dragged = scene.updated(values: ["b": 3])
        XCTAssertEqual(dragged.poly.coef(of: 1), Rational(-3))
        let ext = dragged.marks.filter { $0.type == "extremum" }
        XCTAssertEqual(ext.count, 2)
        XCTAssertEqual(ext[0].x, -1, accuracy: 1e-6)
        XCTAssertEqual(ext[0].y, 2, accuracy: 1e-6)
        XCTAssertEqual(ext[0].kind, "max")

        // 第一幕结尾：3 再改成 1 → x^3 - x
        let second = scene.updated(values: ["b": 1])
        XCTAssertEqual(second.poly.coef(of: 1), Rational(-1))

        // a = 0 → 变成直线，不标极值（不能静默画错）
        let flat = scene.updated(values: ["a": 0])
        XCTAssertTrue(flat.marks.filter { $0.type == "extremum" }.isEmpty)
    }

    func testSceneJSONBindsParamExplicitly() throws {
        let scene = try FunctionSceneBuilder.build("f(x)=x^3-5x")
        let p = scene.payload
        XCTAssertEqual(p.terms.count, 2)
        XCTAssertEqual(p.terms[0].param, "a")
        XCTAssertEqual(p.terms[1].param, "b")
        XCTAssertEqual(p.params[1].value, 5, "学生写 5，滑条上就是 5")
        XCTAssertEqual(p.params[1].sign, -1)
        XCTAssertEqual(p.params[1].min, -10)
        XCTAssertEqual(p.params[0].step, 1)
    }

    func testTangentUsesStudentDerivative() throws {
        let scene = try FunctionSceneBuilder.build("x^3-3x")
        let t = scene.tangent(at: 2)
        XCTAssertEqual(t.slope ?? .nan, 9, accuracy: 1e-9, "f'(2) = 3·4 - 3 = 9")
        XCTAssertEqual(t.y, 2, accuracy: 1e-9)
        // 用学生写对的导数来算：f'(x)=3x^2-3
        let student = try PolyParser.parse("3x^2-3")
        XCTAssertEqual(scene.tangent(at: -1, derivative: student).slope ?? .nan, 0, accuracy: 1e-9)
    }

    func testSamples() throws {
        let scene = try FunctionSceneBuilder.build("x^3-3x")
        let s = scene.samples(count: 241)
        XCTAssertEqual(s.count, 241)
        XCTAssertEqual(s.first!.x, -6, accuracy: 1e-9)
        XCTAssertEqual(s.last!.x, 6, accuracy: 1e-9)
    }

    // MARK: - 高次幂：导数三次以上不再静默返回空

    func testQuarticExtrema() throws {
        // x^4-2x^2 的导数是 4x^3-4x，三个根：-1、0、1
        let scene = try FunctionSceneBuilder.build("x^4-2x^2")
        let ext = scene.marks.filter { $0.type == "extremum" }
        XCTAssertEqual(ext.count, 3)
        XCTAssertEqual(ext[0].x, -1, accuracy: 1e-4)
        XCTAssertEqual(ext[0].kind, "min")
        XCTAssertEqual(ext[1].x, 0, accuracy: 1e-4)
        XCTAssertEqual(ext[1].kind, "max", "x^4 在 0 处是极大，二阶导也为 0 —— 必须看变号")
        XCTAssertEqual(ext[2].x, 1, accuracy: 1e-4)
        XCTAssertEqual(ext[2].kind, "min")
    }

    // MARK: - 错项框

    func testTermBoxEstimateStaysInsideLine() {
        let line = Box(x: 300, y: 100, w: 600, h: 60)
        let box = TermBox.estimate(line: line, label: "f'(x)", body: "3x^2-3x", span: 4..<7)
        XCTAssertGreaterThanOrEqual(box.x, line.x)
        XCTAssertLessThanOrEqual(box.maxX, line.maxX + 1e-9)
        XCTAssertGreaterThan(box.midX, line.midX, "错项在右半边")
        XCTAssertEqual(box.y, line.y)
    }

    func testTermBoxSnapsToStrokes() {
        let line = Box(x: 0, y: 0, w: 600, h: 60)
        let box = TermBox.estimate(line: line, label: nil, body: "3x^2-3x", span: 4..<7)
        let strokes = [
            // 落在错项范围内的两笔
            InkStroke(id: "s1", points: [[box.midX - 10, 20], [box.midX - 5, 40]]),
            InkStroke(id: "s2", points: [[box.midX + 5, 20], [box.midX + 12, 40]]),
            // 不相关的一笔
            InkStroke(id: "s3", points: [[5, 20], [20, 40]]),
        ]
        let snapped = try! XCTUnwrap(TermBox.snap(box, strokes: strokes))
        // 包住那两笔（x 从 midX-10 到 midX+12）并外扩 6 pt；不相关的一笔不参与
        XCTAssertLessThanOrEqual(snapped.x, box.midX - 10 - 5)
        XCTAssertGreaterThanOrEqual(snapped.maxX, box.midX + 12 + 5)
        XCTAssertLessThan(snapped.w, box.w / 2)
    }

    // MARK: - 不许闪退（这是真机上唯一不可救的错误）

    func testGarbageNeverCrashes() {
        let dirty = [
            "", " ", "f'(x)=", "f'(x)=3x^2-++", "???", "f'(x)=\\sqrt{x}",
            // 回归：这些以前会让 Swift 直接 trap
            "f'(x)=99999999999999999999999x",
            "f'(x)=(2x+3)^40",
            "f'(x)=x^123456789",
            "f'(x)=1/0",
            "f'(x)=²",
            "f'(x)=½x",
            "f'(x)=f(1,2)",              // 逗号：解析失败，但不能死循环
            "\\begin{pmatrix}\\end{pmatrix}",
            "\\begin{pmatrix}1&2\\\\3\\end{pmatrix}",
            "\\int dx = 1",
            "\\int_0^1 \\,dx = 1",
        ]
        for text in dirty {
            let a = MathEngineAPI.check(CheckRequest(
                mode: "auto", lines: [.init(id: "L", latex: text)],
                context: .init(functionLatex: "x^3-3x")))
            XCTAssertFalse(a.ok, "垃圾输入不能判成「全对」：\(text)")
            XCTAssertFalse(a.errors.isEmpty, "垃圾输入要有错误项：\(text)")
        }
        // 矩阵、积分、函数三个模式分别过一遍
        for text in dirty {
            _ = MathEngineAPI.check(CheckRequest(mode: "matrix", lines: [.init(id: "M", latex: text)]))
            _ = MathEngineAPI.check(CheckRequest(mode: "integral", lines: [.init(id: "I", latex: text)]))
            _ = MathEngineAPI.check(CheckRequest(mode: "function", lines: [.init(id: "F", latex: text)]))
            _ = MathEngineAPI.function(FunctionRequest(latex: text))
        }
    }

    func testDegenerateMatrixDoesNotCrash() {
        let a = MathEngineAPI.check(CheckRequest(mode: "matrix", lines: [.init(
            id: "M",
            latex: "\\begin{pmatrix}\\end{pmatrix}\\begin{pmatrix}1\\end{pmatrix}=\\begin{pmatrix}1\\end{pmatrix}")]))
        XCTAssertFalse(a.ok)
    }

    func testFunctionModeNeverGradesWrong() {
        let ok = MathEngineAPI.check(CheckRequest(mode: "function", lines: [.init(id: "L1", latex: "f(x)=x^3-5x")]))
        XCTAssertTrue(ok.ok, "函数模式只出图，不批改")
        let bad = MathEngineAPI.check(CheckRequest(mode: "function", lines: [.init(id: "L1", latex: "f(x)=")]))
        XCTAssertFalse(bad.ok)
        XCTAssertEqual(bad.errors.first?.kind, "parse_error")
    }

    // MARK: - 推导等价：两边同除也算等价（旧版会误判）

    func testStepAllowsSameMultiplier() throws {
        XCTAssertTrue(try StepCheck.run(["2x+3=7", "x=2"]).isEmpty, "两边同除 2 是合法的")
        XCTAssertTrue(try StepCheck.run(["2x+3=7", "2x=4"]).isEmpty)
        XCTAssertFalse(try StepCheck.run(["2x+3=7", "2x=10"]).isEmpty)
    }

    // MARK: - 说明模板

    func testExplanationTemplates() throws {
        let cases: [(String, String)] = [
            ("f'(x)=3x^2-3x", "wrong_term"),
            ("f'(x)=2x^2-3", "wrong_coefficient"),
            ("f'(x)=-3x^2-3", "wrong_sign"),
            ("f'(x)=3x^2", "missing_term"),
        ]
        for (latex, kind) in cases {
            let a = MathEngineAPI.check(CheckRequest(mode: "derivative",
                                                     lines: [.init(id: "L", latex: latex)],
                                                     context: .init(functionLatex: "x^3-3x")))
            XCTAssertEqual(a.errors.first?.kind, kind, latex)
            let e = try XCTUnwrap(a.errors.first)
            let ex = try XCTUnwrap(e.explanation, "direct 模式每条错误都要有说明：\(latex)")
            XCTAssertFalse(ex.isEmpty)
            XCTAssertFalse(ex.contains("\\frac"), "说明是给人读的，不该出现 LaTeX 记号：\(ex)")
        }
    }

    // MARK: - 契约：能解码 v3 的请求，响应能解回来

    func testDecodeContractRequests() throws {
        let dir = try XCTUnwrap(resourceDir()?.appendingPathComponent("contracts/v3"))
        let decoder = MathEngineJSON.decoder()

        let checkReq = try decoder.decode(CheckRequest.self,
                                          from: Data(contentsOf: dir.appendingPathComponent("check.request.json")))
        XCTAssertEqual(checkReq.feedbackMode, .direct)
        XCTAssertEqual(checkReq.lines.first?.id, "L2", "line_id 也要认")
        XCTAssertEqual(checkReq.lines.first?.revision, 3)
        XCTAssertEqual(checkReq.context?.functionLatex, "f(x)=x^3-5x")

        let fnReq = try decoder.decode(FunctionRequest.self,
                                       from: Data(contentsOf: dir.appendingPathComponent("function.request.json")))
        XCTAssertEqual(fnReq.latex, "f(x)=x^3-5x")

        let geoReq = try decoder.decode(GeometryRequest.self,
                                        from: Data(contentsOf: dir.appendingPathComponent("geometry.request.json")))
        XCTAssertEqual(geoReq.points?.count, 4)

        // 响应：解码回来再编码，字段不能丢
        let resp = try decoder.decode(Annotation.self,
                                      from: Data(contentsOf: dir.appendingPathComponent("check.response.json")))
        XCTAssertEqual(resp.errors.first?.expectedLatex, "-5")
        XCTAssertEqual(resp.errors.first?.lineId, "L2")
        XCTAssertEqual(resp.errors.first?.bboxSource, "term")
        XCTAssertNotNil(resp.errors.first?.explanation)
    }

    func testSocraticContractFileHasNoAnswer() throws {
        let dir = try XCTUnwrap(resourceDir()?.appendingPathComponent("contracts/v3"))
        let socratic = try String(contentsOf: dir.appendingPathComponent("check.response.socratic.json"), encoding: .utf8)
        XCTAssertTrue(socratic.contains("\"socratic\""))
        XCTAssertFalse(socratic.contains("expected_latex"), "socratic 文件里不许出现 expected_latex")
        XCTAssertFalse(socratic.contains("\"explanation\""), "socratic 文件里不许出现 explanation")
    }

    func testGeometryResolvesMidpoint() {
        let r = MathEngineAPI.geometry(GeometryRequest(
            mode: "geometry",
            points: [.init(id: "A", x: 0, y: 0, free: true),
                     .init(id: "B", x: 2, y: 0, free: true),
                     .init(id: "C", x: 0, y: 2, free: true)],
            relations: [.init(type: "midpoint", of: ["B", "C"], point: "Ma")]))
        XCTAssertTrue(r.ok)
        let m = r.scene?.points.first { $0.id == "Ma" }
        XCTAssertEqual(m?.x ?? -1, 1, accuracy: 1e-9)
        XCTAssertEqual(m?.free, false)
        XCTAssertEqual(r.scene?.relations.first?.point, "Ma")
    }
}
