//
//  Parity.swift
//  MathEngine
//
//  与 Python 参考实现（server/，SymPy）逐条对账。
//  夹具由 `python server/tools/export_parity.py` 生成，XCTest 和 `p4tool parity` 都读它。
//
//  为什么要有它：P4 的验收标准是「/check 对 10 条全部判对」。现在有两套实现，
//  只有它们对同一批输入的判断完全一致，"Swift 版能替代 Python 版"这句话才成立。
//

import Foundation

public enum Parity {

    public struct Case: Decodable {
        public struct Err: Decodable {
            public var kind: String
            public var wrongLatex: String?
            public var expectedLatex: String?
            public var charSpan: [Int]?

            private enum CodingKeys: String, CodingKey {
                case kind, wrongLatex = "wrong_latex", expectedLatex = "expected_latex", charSpan = "char_span"
            }
        }
        public var id: String
        public var mode: String
        public var latex: String
        public var functionLatex: String?
        public var ok: Bool
        public var errors: [Err]
        /// Python 归一化后的正文；char_span 相对它。两边归一化写法不同时，只跳过 span 的比较
        public var checkedLatex: String?

        private enum CodingKeys: String, CodingKey {
            case id, mode, latex, ok, errors, checkedLatex = "checked_latex", functionLatex = "function_latex"
        }
    }

    public struct FunctionCase: Decodable {
        public struct Extremum: Decodable {
            public var kind: String
            public var x: Double
            public var y: Double
        }
        public var id: String
        public var latex: String
        public var extrema: [Extremum]
    }

    public struct File: Decodable {
        public var checks: [Case]
        public var functions: [FunctionCase]
    }

    public struct Report {
        public var failures: Int
        public var total: Int
        public var lines: [String]
        public var text: String { lines.joined(separator: "\n") }
    }

    public static func load(_ data: Data) throws -> File {
        let decoder = JSONDecoder()
        return try decoder.decode(File.self, from: data)
    }

    public static func run(_ data: Data) throws -> Report {
        try compare(load(data))
    }

    public static func compare(_ file: File) -> Report {
        var lines: [String] = []
        var failures = 0

        for c in file.checks {
            let req = CheckRequest(mode: c.mode,
                                   lines: [.init(id: "L1", latex: c.latex)],
                                   context: c.functionLatex.map { CheckRequest.Context(functionLatex: $0) })
            let got = MathEngineAPI.check(req)
            var problems: [String] = []
            if got.ok != c.ok { problems.append("ok 判反了：Swift \(got.ok) / Python \(c.ok)") }
            if got.errors.count != c.errors.count {
                problems.append("错误条数：Swift \(got.errors.count) / Python \(c.errors.count)")
            }
            for (g, w) in zip(got.errors, c.errors) {
                if g.kind != w.kind { problems.append("kind：Swift \(g.kind) / Python \(w.kind)") }
                if g.wrongLatex != w.wrongLatex {
                    problems.append("wrong_latex：Swift \(g.wrongLatex ?? "null") / Python \(w.wrongLatex ?? "null")")
                }
                if g.expectedLatex != w.expectedLatex {
                    problems.append("expected_latex：Swift \(g.expectedLatex ?? "null") / Python \(w.expectedLatex ?? "null")")
                }
                // char_span 只在两边归一化正文一致时才可比（例如 x^{2} 与 x^(2) 的字符数不同）
                if let want = c.checkedLatex, got.checked.rhsLatex.first == want,
                   let span = w.charSpan, let gs = g.charSpan, span != gs {
                    problems.append("char_span：Swift \(gs) / Python \(span)")
                }
            }
            if problems.isEmpty {
                lines.append("PASS \(c.id)  \(c.latex)")
            } else {
                failures += 1
                lines.append("FAIL \(c.id)  \(c.latex)\n      " + problems.joined(separator: "\n      "))
            }
        }

        for f in file.functions {
            let resp = MathEngineAPI.function(FunctionRequest(latex: f.latex, variable: nil, view: nil, lines: nil))
            var problems: [String] = []
            let got = (resp.scene?.function.marks ?? []).filter { $0.type == "extremum" }
            if got.count != f.extrema.count {
                problems.append("极值点个数：Swift \(got.count) / Python \(f.extrema.count)")
            }
            for (g, w) in zip(got, f.extrema) {
                if Swift.abs(g.x - w.x) > 1e-4 || Swift.abs(g.y - w.y) > 1e-4 {
                    problems.append("极值点：Swift (\(g.x), \(g.y)) / Python (\(w.x), \(w.y))")
                }
                if (g.kind ?? "") != w.kind { problems.append("极大极小：Swift \(g.kind ?? "null") / Python \(w.kind)") }
            }
            if problems.isEmpty {
                lines.append("PASS \(f.id)  \(f.latex)")
            } else {
                failures += 1
                lines.append("FAIL \(f.id)  \(f.latex)\n      " + problems.joined(separator: "\n      "))
            }
        }

        let total = file.checks.count + file.functions.count
        lines.append("")
        lines.append("对账：\(total - failures)/\(total) 一致")
        return Report(failures: failures, total: total, lines: lines)
    }
}
