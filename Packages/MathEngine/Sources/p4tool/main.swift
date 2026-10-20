//
//  p4tool — 命令行小工具（Mac 上 `swift run p4tool <子命令>`）
//
//    p4tool contracts --out DIR   从 Swift 引擎生成 contracts/v3/*.json（契约以真代码为准）
//    p4tool parity FILE           与 Python 参考实现逐条对账（12 条批改 + 3 条场景）
//    p4tool demo                  在终端打印黄金路径每一步的返回
//
//  App 和 Vapor 都链接同一个 MathEngine 库，这里只是把它的输出打出来。
//

import Foundation
import MathEngine

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write(("错误：" + msg + "\n").data(using: .utf8)!)
    exit(2)
}

let args = Array(CommandLine.arguments.dropFirst())
let cmd = args.first ?? "demo"

func write(_ json: String, to url: URL) throws {
    try json.write(to: url, atomically: true, encoding: .utf8)
}

switch cmd {

case "contracts":
    guard let i = args.firstIndex(of: "--out"), i + 1 < args.count else {
        fail("用法：p4tool contracts --out <目录>")
    }
    let dir = URL(fileURLWithPath: args[i + 1])
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    // 第二幕的黄金路径：写错 → 擦掉 → 改写 → 改对
    let wrong = CheckRequest(
        mode: "derivative",
        lines: [.init(id: "L2", latex: "f'(x)=3x^2-5x", bbox: Box(x: 318, y: 336, w: 372, h: 44), revision: 3)],
        context: .init(functionLatex: "f(x)=x^3-5x", variable: "x"),
        options: .init(withScene: true, maxErrors: 3),
        strokes: [InkStroke(id: "s17", points: [[318, 350, 1.20, 0.62], [319.4, 351.1, 1.23, 0.66]])],
        region: .init(x: 40, y: 320, w: 600, h: 140, scale: 2),
        feedbackMode: .direct
    )
    let fn = FunctionRequest(latex: "f(x)=x^3-5x", variable: "x", view: nil,
                             lines: [.init(id: "L1", latex: "f(x)=x^3-5x", bbox: Box(x: 40, y: 120, w: 420, h: 90))])
    let geo = GeometryRequest(mode: "geometry",
                              points: [.init(id: "A", x: 340, y: 424, free: true),
                                       .init(id: "B", x: 88, y: 676, free: true),
                                       .init(id: "C", x: 592, y: 676, free: true),
                                       .init(id: "Ma", x: 340, y: 676, free: false)],
                              relations: [.init(type: "midpoint", of: ["B", "C"], point: "Ma")],
                              context: .init(template: "triangle_median"))

    var socratic = wrong
    socratic.feedbackMode = .socratic

    try write(MathEngineJSON.string(wrong), to: dir.appendingPathComponent("check.request.json"))
    try write(MathEngineJSON.string(MathEngineAPI.check(wrong)), to: dir.appendingPathComponent("check.response.json"))
    try write(MathEngineJSON.string(MathEngineAPI.check(socratic)), to: dir.appendingPathComponent("check.response.socratic.json"))
    try write(MathEngineJSON.string(fn), to: dir.appendingPathComponent("function.request.json"))
    try write(MathEngineJSON.string(MathEngineAPI.function(fn)), to: dir.appendingPathComponent("function.response.json"))
    try write(MathEngineJSON.string(geo), to: dir.appendingPathComponent("geometry.request.json"))
    try write(MathEngineJSON.string(MathEngineAPI.geometry(geo)), to: dir.appendingPathComponent("geometry.response.json"))
    print("已写到 \(dir.path)：7 份")

case "parity":
    guard args.count > 1 else { fail("用法：p4tool parity <contracts/parity_cases.json>") }
    let data = try! Data(contentsOf: URL(fileURLWithPath: args[1]))
    let report = try! Parity.run(data)
    print(report.text)
    exit(report.failures == 0 ? 0 : 1)

case "demo":
    let lines = [
        ("L1 函数", CheckRequest(mode: "function", lines: [.init(id: "L1", latex: "f(x)=x^3-5x")])),
        ("L2 写错", CheckRequest(mode: "derivative", lines: [.init(id: "L2", latex: "f'(x)=3x^2-5x")],
                                context: .init(functionLatex: "x^3-5x"))),
        ("L2 改对", CheckRequest(mode: "derivative", lines: [.init(id: "L2", latex: "f'(x)=3x^2-5")],
                                context: .init(functionLatex: "x^3-5x"))),
        ("矩阵", CheckRequest(mode: "matrix", lines: [.init(
            id: "M",
            latex: "\\begin{pmatrix}1 & 2 \\\\ 3 & 4\\end{pmatrix}\\begin{pmatrix}5 & 6 \\\\ 7 & 8\\end{pmatrix}=\\begin{pmatrix}19 & 22 \\\\ 43 & 49\\end{pmatrix}")])),
        ("积分", CheckRequest(mode: "integral", lines: [.init(id: "I", latex: "\\int 2x\\,dx = x^2/2")])),
    ]
    for (name, req) in lines {
        print("── \(name)")
        print(MathEngineJSON.string(MathEngineAPI.check(req)))
    }

default:
    print("""
    用法：
      p4tool contracts --out DIR   生成 contracts/v3/*.json
      p4tool parity FILE           与 Python 参考实现对账
      p4tool demo                  打印黄金路径的返回
    """)
}
