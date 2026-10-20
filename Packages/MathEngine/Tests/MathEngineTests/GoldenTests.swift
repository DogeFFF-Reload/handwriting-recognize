//
//  GoldenTests.swift
//  MathEngine
//
//  这些期望值不是手写的，是从已验证的 Python 参考实现导出的（contracts/golden_cases.json）。
//  两边跑同一份夹具，就是为了让 Swift 的移植"有标准答案"。
//
//  在 Mac 上：cd swift/MathEngine && swift test
//

import Foundation
import XCTest
@testable import MathEngine

final class GoldenTests: XCTestCase {

    // MARK: - 读夹具

    static var golden: [String: Any] = [:]

    override class func setUp() {
        super.setUp()
        guard let url = Bundle.module.url(forResource: "golden_cases", withExtension: "json") else {
            XCTFail("找不到 golden_cases.json（检查 Package.swift 的 resources）")
            return
        }
        do {
            let data = try Data(contentsOf: url)
            if let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                GoldenTests.golden = obj
            }
        } catch {
            XCTFail("读夹具失败：\(error)")
        }
    }

    func cases(_ key: String) -> [[String: Any]] {
        (GoldenTests.golden[key] as? [[String: Any]]) ?? []
    }

    func assertTerms(_ poly: Poly, _ expected: [[String: Any]], _ id: String,
                     file: StaticString = #filePath, line: UInt = #line) {
        let want = expected.map { (coef: ($0["coef"] as? Double) ?? 0, pow: ($0["pow"] as? Int) ?? 0) }
        XCTAssertEqual(poly.terms.count, want.count, "\(id): 项数不对", file: file, line: line)
        for (i, t) in poly.terms.enumerated() where i < want.count {
            XCTAssertEqual(t.coef.doubleValue, want[i].coef, accuracy: 1e-9, "\(id): 系数不对", file: file, line: line)
            XCTAssertEqual(t.pow, want[i].pow, "\(id): 幂次不对", file: file, line: line)
        }
    }

    // MARK: - 解析

    func testParseCases() throws {
        let list = cases("parse")
        XCTAssertFalse(list.isEmpty, "parse 用例为空")
        for c in list {
            let id = c["id"] as? String ?? "?"
            let latex = c["latex"] as? String ?? ""
            let expected = c["terms"] as? [[String: Any]] ?? []
            do {
                let line = try StudentLine.parse(latex)
                assertTerms(line.poly, expected, id)
            } catch {
                XCTFail("\(id) 解析失败：\(error) [\(latex)]")
            }
        }
    }

    func testEquationResidual() throws {
        for c in cases("equation") {
            let id = c["id"] as? String ?? "?"
            let latex = c["latex"] as? String ?? ""
            let expected = c["diff_terms"] as? [[String: Any]] ?? []
            let residual = try DerivativeCheck.residual(latex)
            assertTerms(residual, expected, id)
        }
    }

    // MARK: - 函数场景

    func testFunctionScenes() throws {
        for c in cases("function") {
            let id = c["id"] as? String ?? "?"
            let latex = c["latex"] as? String ?? ""
            let scene = try FunctionSceneBuilder.build(latex)
            assertTerms(Poly(scene.terms), c["terms"] as? [[String: Any]] ?? [], id)

            let wantParams = c["params"] as? [[String: Any]] ?? []
            XCTAssertEqual(scene.params.count, wantParams.count, "\(id): 滑条个数不对")
            for (i, p) in scene.params.enumerated() where i < wantParams.count {
                XCTAssertEqual(p.value, (wantParams[i]["value"] as? Double) ?? -1, accuracy: 1e-9, "\(id): 滑条值不对")
                XCTAssertEqual(p.sign, (wantParams[i]["sign"] as? Int) ?? 0, "\(id): 滑条符号不对")
            }

            let wantMarks = c["extrema"] as? [[String: Any]] ?? []
            let gotMarks = scene.marks.filter { $0.type == "extremum" }
            XCTAssertEqual(gotMarks.count, wantMarks.count, "\(id): 极值点个数不对")
            for (i, m) in wantMarks.enumerated() where i < gotMarks.count {
                XCTAssertEqual(gotMarks[i].x, (m["x"] as? Double) ?? .nan, accuracy: 1e-3, "\(id): 极值 x 不对")
                XCTAssertEqual(gotMarks[i].y, (m["y"] as? Double) ?? .nan, accuracy: 1e-3, "\(id): 极值 y 不对")
                XCTAssertEqual(gotMarks[i].kind ?? "", (m["kind"] as? String) ?? "", "\(id): 极大/极小判反了")
            }
        }
    }

    // MARK: - 求导批改（第二幕）

    func testDerivativeCases() throws {
        for c in cases("derivative") {
            let id = c["id"] as? String ?? "?"
            let context = c["context"] as? String ?? ""
            let latex = c["latex"] as? String ?? ""
            let wantOK = c["ok"] as? Bool ?? false
            let wantErrors = c["errors"] as? [[String: Any]] ?? []

            let defects = try DerivativeCheck.run(functionLatex: context, lineLatex: latex)
            XCTAssertEqual(defects.isEmpty, wantOK, "\(id): 对错判反了 [\(latex)]")
            XCTAssertEqual(defects.count, wantErrors.count, "\(id): 错误条数不对")
            for (i, want) in wantErrors.enumerated() where i < defects.count {
                let got = defects[i]
                XCTAssertEqual(got.kind.rawValue, (want["kind"] as? String) ?? "", "\(id): 错误类型不对")
                XCTAssertEqual(got.wrongLatex, want["wrong_latex"] as? String, "\(id): 错项原文不对")
                XCTAssertEqual(got.expectedLatex, want["expected_latex"] as? String, "\(id): 正确项不对")
                if let span = want["span"] as? [Int], span.count == 2, let gotSpan = got.span {
                    XCTAssertEqual(gotSpan.lowerBound, span[0], "\(id): 字符区间起点不对")
                    XCTAssertEqual(gotSpan.upperBound, span[1], "\(id): 字符区间终点不对")
                }
            }
        }
    }

    // MARK: - 加分项

    func testMatrixCases() throws {
        for c in cases("matrix") {
            let id = c["id"] as? String ?? "?"
            let latex = c["latex"] as? String ?? ""
            let wantOK = c["ok"] as? Bool ?? false
            let defects = try MatrixCheck.run(latex)
            XCTAssertEqual(defects.isEmpty, wantOK, "\(id): 矩阵对错判反了")
            if let first = (c["errors"] as? [[String: Any]])?.first, let got = defects.first {
                XCTAssertEqual(got.row, first["row"] as? Int, "\(id): 行号不对")
                XCTAssertEqual(got.col, first["col"] as? Int, "\(id): 列号不对")
                XCTAssertEqual(got.expectedLatex, first["expected_latex"] as? String, "\(id): 正确元素不对")
            }
        }
    }

    func testIntegralCases() throws {
        for c in cases("integral") {
            let id = c["id"] as? String ?? "?"
            let latex = c["latex"] as? String ?? ""
            let wantOK = c["ok"] as? Bool ?? false
            do {
                let defects = try IntegralCheck.run(latex)
                XCTAssertEqual(defects.isEmpty, wantOK, "\(id): 积分对错判反了 [\(latex)]")
            } catch {
                XCTFail("\(id) 积分解析失败：\(error)")
            }
        }
    }

    func testStepCases() throws {
        for c in cases("step") {
            let id = c["id"] as? String ?? "?"
            let lines = c["lines"] as? [String] ?? []
            let wantOK = c["ok"] as? Bool ?? false
            let defects = try StepCheck.run(lines)
            XCTAssertEqual(defects.isEmpty, wantOK, "\(id): 推导等价判反了")
        }
    }

    // MARK: - 边界

    func testDirtyInputDoesNotCrash() {
        let dirty = ["", "f'(x)=", "f'(x)=3x^2-++", "???", "f'(x)=\\sqrt{x}"]
        for text in dirty {
            let defects = try? DerivativeCheck.run(functionLatex: "x^3-3x", lineLatex: text)
            if let d = defects, d.isEmpty {
                XCTFail("垃圾输入被判成「全对」：\(text)")
            }
        }
    }

    func testHintNeverLeaksAnswer() throws {
        let defects = try DerivativeCheck.run(functionLatex: "x^3-3x", lineLatex: "f'(x)=3x^2-3x")
        guard let first = defects.first else { return XCTFail("应该报错") }
        XCTAssertEqual(first.expectedLatex, "-3")
        let stripped = first.fallbackHint().replacingOccurrences(of: first.wrongLatex ?? "", with: "")
        XCTAssertFalse(stripped.contains("-3"), "兜底提示泄露了答案：\(stripped)")
    }

    func testHintGuardRejectsAnswer() {
        // 模型把答案说出来了 → 必须换成兜底
        let (text, why) = HintGuard.safe("这一项求导后是 -3。",
                                        fallback: "先单独对它求一次导，会剩下什么？",
                                        expected: "-3",
                                        wrong: "-3x")
        XCTAssertNotEqual(text, "这一项求导后是 -3。")
        XCTAssertFalse(why.isEmpty)

        // 学生自己写的 -3x 里含 -3，不算泄题
        let issues = HintGuard.problems("你写的 -3x 里，x 这一项求导后还剩什么？",
                                        expected: "-3", wrong: "-3x")
        XCTAssertTrue(issues.isEmpty, "\(issues)")
    }

    func testGeometryMidpointSurvivesDrag() {
        var points = [
            GeoPoint(id: "A", x: 0, y: 0, free: true),
            GeoPoint(id: "B", x: 2, y: 0, free: true),
            GeoPoint(id: "C", x: 0, y: 2, free: true),
        ]
        let rel = GeoRelation(type: "midpoint", of: ["B", "C"], point: "M")
        points = Geometry.resolve(points: points, relations: [rel])
        XCTAssertEqual(points.first { $0.id == "M" }?.x ?? -1, 1.0, accuracy: 1e-9)

        // 拖动 B，M 必须跟着变
        points = points.map { $0.id == "B" ? GeoPoint(id: "B", x: 4, y: 0, free: true) : $0 }
        points = Geometry.resolve(points: points, relations: [rel])
        XCTAssertEqual(points.first { $0.id == "M" }?.x ?? -1, 2.0, accuracy: 1e-9)
    }
}
