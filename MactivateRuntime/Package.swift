// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MactivateRuntime",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "MactivateRuntime", targets: ["MactivateRuntime"])
    ],
    dependencies: [
        .package(path: "../MactuationCore")
    ],
    targets: [
        .target(
            name: "MactivateRuntime",
            dependencies: [
                .product(name: "MactuationCore", package: "MactuationCore"),
                .product(name: "MactuationHardware", package: "MactuationCore")
            ],
            linkerSettings: [.linkedFramework("AppKit")]
        ),
        .testTarget(
            name: "MactivateRuntimeTests",
            dependencies: [
                "MactivateRuntime",
                .product(name: "MactuationCore", package: "MactuationCore")
            ]
        )
    ]
)
