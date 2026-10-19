// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SceneUI",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "SceneUI", targets: ["SceneUI"])
    ],
    dependencies: [
        // 纯 Swift 的 LaTeX 排版（MIT），识别回显、正确项、右侧公式共用。
        .package(url: "https://github.com/mgriebling/SwiftMath.git", from: "1.4.0")
    ],
    targets: [
        .target(name: "SceneUI", dependencies: [.product(name: "SwiftMath", package: "SwiftMath")])
    ]
)
