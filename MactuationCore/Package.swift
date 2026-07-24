// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MactuationCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "MactuationCore", targets: ["MactuationCore"])
    ],
    targets: [
        .target(name: "MactuationCore"),
        .testTarget(name: "MactuationCoreTests", dependencies: ["MactuationCore"])
    ]
)
