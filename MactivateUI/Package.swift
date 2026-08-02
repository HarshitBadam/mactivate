// swift-tools-version:5.9
import PackageDescription

// `MactivateDesign` is Foundation-only so the presentation logic, configuration
// model, and engine-facing ports build and test anywhere, including the Linux
// CI this repository was initialized in. `MactivateInterface` and `MactivateApp`
// hold the SwiftUI/AppKit surfaces; their sources are `#if os(macOS)`-guarded so
// the whole package still resolves off-Mac.
let package = Package(
    name: "MactivateUI",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MactivateDesign", targets: ["MactivateDesign"]),
        .library(name: "MactivateInterface", targets: ["MactivateInterface"]),
        .executable(name: "MactivateApp", targets: ["MactivateApp"])
    ],
    dependencies: [
        .package(path: "../MactuationCore")
    ],
    targets: [
        .target(
            name: "MactivateDesign",
            dependencies: [.product(name: "MactuationCore", package: "MactuationCore")]
        ),
        .target(name: "MactivateInterface", dependencies: ["MactivateDesign"]),
        .executableTarget(name: "MactivateApp", dependencies: ["MactivateInterface"]),
        .testTarget(name: "MactivateDesignTests", dependencies: ["MactivateDesign"])
    ]
)
