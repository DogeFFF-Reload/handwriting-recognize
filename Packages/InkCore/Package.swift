// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "InkCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "InkCore", targets: ["InkCore"])
    ],
    targets: [
        .target(name: "InkCore"),
        // 不依赖 UIKit / PencilKit 的逻辑都在这里测；Linux 和 macOS 上都能 `swift test`。
        .testTarget(name: "InkCoreTests", dependencies: ["InkCore"])
    ]
)
