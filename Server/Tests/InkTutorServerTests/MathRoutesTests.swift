import Foundation
import XCTest
@testable import InkTutorServer

final class MathRoutesTests: XCTestCase {
    private func object(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func checkBody(_ derivative: String, mode: String) -> Data {
        Data("""
        {"mode":"derivative","feedback_mode":"\(mode)",
         "lines":[{"line_id":"L2","latex":"\(derivative)","bbox":[40,320,600,140]}],
         "context":{"function_latex":"x^3-3x"}}
        """.utf8)
    }

    /// 黄金路径第二幕：错项 -3x 被判出、登记提示；socratic 的响应不带正确项，但提示里有。
    func testCheckWrongLineRegistersHintWithoutLeakingAnswer() async throws {
        var registered: [HintRequest] = []
        let data = try await MathRoutes.check(checkBody("f'(x)=3x^2-3x", mode: "socratic")) { h in
            registered.append(h)
            return "7f3a"
        }
        let json = try object(data)
        XCTAssertEqual(json["ok"] as? Bool, false)
        XCTAssertEqual(json["hint_url"] as? String, "/hint/7f3a")
        let errors = try XCTUnwrap(json["errors"] as? [[String: Any]])
        XCTAssertEqual(errors.first?["wrong_latex"] as? String, "-3x")
        XCTAssertNil(errors.first?["expected_latex"])
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("3x^2-3\""))

        XCTAssertEqual(registered.count, 1)
        XCTAssertEqual(registered.first?.wrongLatex, "-3x")
        XCTAssertEqual(registered.first?.expectedLatex, "-3")
        XCTAssertEqual(registered.first?.functionLatex, "x^3-3x")
        XCTAssertEqual(registered.first?.feedbackMode, "socratic")
    }

    func testCheckCorrectLineHasNoHint() async throws {
        var calls = 0
        let data = try await MathRoutes.check(checkBody("f'(x)=3x^2-3", mode: "direct")) { _ in calls += 1; return "x" }
        let json = try object(data)
        XCTAssertEqual(json["ok"] as? Bool, true)
        XCTAssertNil(json["hint_url"])
        XCTAssertEqual(calls, 0)
    }

    func testFunctionGivesExtrema() throws {
        let json = try object(try MathRoutes.function(Data(#"{"latex":"f(x)=x^3-3x"}"#.utf8)))
        XCTAssertEqual(json["ok"] as? Bool, true)
        let scene = try XCTUnwrap(json["scene"] as? [String: Any])
        let function = try XCTUnwrap(scene["function"] as? [String: Any])
        let marks = try XCTUnwrap(function["marks"] as? [[String: Any]])
        let xs = marks.filter { ($0["type"] as? String) == "extremum" }.compactMap { $0["x"] as? Double }.sorted()
        XCTAssertEqual(xs, [-1, 1])
    }

    func testBadInputIsOkFalseNotACrash() throws {
        let json = try object(try MathRoutes.function(Data(#"{"latex":"\\sin x"}"#.utf8)))
        XCTAssertEqual(json["ok"] as? Bool, false)
    }
}
