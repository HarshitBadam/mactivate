// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MactuationProbe",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(name: "MactuationCore", path: "../../packages/core"),
        .package(name: "MactuationResearch", path: "../analysis")
    ],
    targets: [
        .executableTarget(
            name: "mactuation-probe",
            dependencies: [
                .product(name: "MactuationCore", package: "MactuationCore"),
                .product(name: "MactuationHardware", package: "MactuationCore"),
                .product(name: "MactuationCapture", package: "MactuationCore"),
                .product(name: "MactuationResearch", package: "MactuationResearch")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreMotion")
            ]
        )
    ]
)
