// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MactuationCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "MactuationCore", targets: ["MactuationCore"]),
        .library(name: "MactuationHardware", targets: ["MactuationHardware"]),
        .library(name: "MactuationCapture", targets: ["MactuationCapture"]),
        .library(name: "MactuationTestSupport", targets: ["MactuationTestSupport"])
    ],
    targets: [
        .target(name: "MactuationCore"),
        .target(
            name: "MactuationHardware",
            dependencies: ["MactuationCore"],
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .target(
            name: "MactuationCapture",
            dependencies: ["MactuationCore"]
        ),
        .target(
            name: "MactuationTestSupport",
            dependencies: ["MactuationCore", "MactuationCapture"]
        ),
        .testTarget(
            name: "MactuationCoreTests",
            dependencies: ["MactuationCore", "MactuationTestSupport"],
            resources: [.process("Fixtures")]
        ),
        .testTarget(
            name: "MactuationHardwareTests",
            dependencies: ["MactuationHardware", "MactuationCore"]
        ),
        .testTarget(
            name: "MactuationCaptureTests",
            dependencies: ["MactuationCapture", "MactuationTestSupport"]
        ),
        .testTarget(
            name: "MactuationTestSupportTests",
            dependencies: ["MactuationTestSupport", "MactuationCapture", "MactuationCore"]
        )
    ]
)
