// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MactuationResearch",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "MactuationResearch", targets: ["MactuationResearch"])
    ],
    dependencies: [
        .package(name: "MactuationCore", path: "../../packages/core")
    ],
    targets: [
        .target(
            name: "MactuationResearch",
            dependencies: [
                .product(name: "MactuationCore", package: "MactuationCore"),
                .product(name: "MactuationCapture", package: "MactuationCore")
            ]
        ),
        .testTarget(
            name: "MactuationResearchTests",
            dependencies: [
                "MactuationResearch",
                .product(name: "MactuationCore", package: "MactuationCore"),
                .product(name: "MactuationCapture", package: "MactuationCore"),
                .product(name: "MactuationTestSupport", package: "MactuationCore")
            ]
        )
    ]
)
