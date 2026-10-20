// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MathEngine",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "MathEngine", targets: ["MathEngine"]),
        // 命令行小工具：生成契约、与 Python 参考实现对账、打印黄金路径
        .executable(name: "p4tool", targets: ["p4tool"]),
    ],
    targets: [
        .target(name: "MathEngine"),
        .executableTarget(name: "p4tool", dependencies: ["MathEngine"]),
        .testTarget(
            name: "MathEngineTests",
            dependencies: ["MathEngine"],
            resources: [.copy("golden_cases.json"), .copy("contracts")]
        ),
    ]
)
