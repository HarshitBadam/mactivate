// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MactuationProbe",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(path: "../MactuationCore")
    ],
    targets: [
        .executableTarget(
            name: "mactuation-probe",
            dependencies: [
                .product(name: "MactuationCore", package: "MactuationCore"),
                .product(name: "MactuationHardware", package: "MactuationCore")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreMotion")
            ]
        )
    ]
)
