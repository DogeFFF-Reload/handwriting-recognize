// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "InkCore",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "InkCore", targets: ["InkCore"])
    ],
    targets: [
        .target(name: "InkCore")
    ]
)
