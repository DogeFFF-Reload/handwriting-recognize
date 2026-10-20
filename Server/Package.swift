// swift-tools-version: 5.9
import PackageDescription

// 跑在演示用的 Mac 上：扣住百炼 Key，提供 /recognize（Qwen 看图识别）、/check /function /geometry（MathEngine）、/hint（提示流）和断网回放。
// iPad 和 Mac 连同一个热点。启动：cd Server && swift run InkTutorServer
let package = Package(
    name: "InkTutorServer",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.99.0"),
        .package(path: "../Packages/InkCore"),
        .package(path: "../Packages/MathEngine"),
    ],
    targets: [
        .executableTarget(
            name: "InkTutorServer",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "InkCore", package: "InkCore"),
                .product(name: "MathEngine", package: "MathEngine"),
            ]
        ),
        .testTarget(name: "InkTutorServerTests", dependencies: ["InkTutorServer"]),
    ]
)
