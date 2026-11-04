// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "AdaptivePracticeScore",
    platforms: [
        .iOS(.v13),
        .macOS(.v11)
    ],
    products: [
        .library(name: "AdaptivePracticeScore", targets: ["AdaptivePracticeScore"])
    ],
    targets: [
        .target(name: "AdaptivePracticeScore"),
        .testTarget(name: "AdaptivePracticeScoreTests", dependencies: ["AdaptivePracticeScore"])
    ]
)