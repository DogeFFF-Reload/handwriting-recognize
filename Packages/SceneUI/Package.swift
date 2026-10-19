// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SceneUI",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "SceneUI", targets: ["SceneUI"])
    ],
    targets: [
        .target(name: "SceneUI")
    ]
)
