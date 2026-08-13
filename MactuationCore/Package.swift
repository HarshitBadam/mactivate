// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MactuationCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "MactuationCore", targets: ["MactuationCore"]),
        .library(name: "MactuationHardware", targets: ["MactuationHardware"])
    ],
    targets: [
        .target(name: "MactuationCore"),
        .target(
            name: "MactuationHardware",
            dependencies: ["MactuationCore"],
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .testTarget(
            name: "MactuationCoreTests",
            dependencies: ["MactuationCore"],
            resources: [.process("Fixtures")]
        ),
        .testTarget(
            name: "MactuationHardwareTests",
            dependencies: ["MactuationHardware", "MactuationCore"]
        )
    ]
)
