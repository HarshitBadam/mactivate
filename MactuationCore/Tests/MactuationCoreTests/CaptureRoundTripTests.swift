import XCTest
@testable import MactuationCore

final class CaptureRoundTripTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mactuation-tests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeManifest() -> SessionManifest {
        SessionManifest(label: "test", startedAt: Date(timeIntervalSince1970: 1_700_000_000),
                        toolVersion: "test-0")
    }

    func testSamplesSurviveWriteAndRead() throws {
        let source = MockSensorSource(configuration: .init(
            seed: 42, duration: 2,
            taps: [(time: 0.5, amplitude: 0.03)],
            covers: [(start: 1.0, end: 1.5)]))
        let original = source.generate()

        let writer = try CaptureWriter(directory: tempDir, manifest: makeManifest())
        for sample in original {
            try writer.append(sample)
        }
        writer.addLabel(LabelSpan(start: 0.5, end: 0.6, label: "palm_single", repetition: 1,
                                  intensity: "soft", notes: "with, comma and \"quotes\""))
        writer.recordSensorMetadata(path: .spuAccelerometer, effectiveRateHz: 100,
                                    acquisitionParameters: ["ReportInterval": "5428500"])
        try writer.finalize()

        let reader = try CaptureReader(directory: tempDir)
        let restored = try reader.mergedSamples()
        XCTAssertEqual(restored, original)

        let labels = try reader.labels()
        XCTAssertEqual(labels.count, 1)
        XCTAssertEqual(labels[0].label, "palm_single")
        XCTAssertEqual(labels[0].notes, "with, comma and \"quotes\"")

        let record = reader.manifest.sensors.first { $0.path == .spuAccelerometer }
        XCTAssertEqual(record?.effectiveRateHz, 100)
        XCTAssertEqual(record?.acquisitionParameters["ReportInterval"], "5428500")
    }

    func testExtremeDoublesRoundTrip() throws {
        let awkward: [SensorSample] = [
            .imu(path: .spuAccelerometer,
                 sample: IMUSample(timestamp: 0.1 + 0.2, x: 1e-300, y: -1e300, z: .pi)),
            .als(path: .spuAmbientLight,
                 sample: ALSSample(timestamp: 1.0000000000000002, lux: 0.30000000000000004,
                                   channels: [1.5e-10, 7]))
        ]
        let writer = try CaptureWriter(directory: tempDir, manifest: makeManifest())
        for sample in awkward {
            try writer.append(sample)
        }
        try writer.finalize()

        let restored = try CaptureReader(directory: tempDir).mergedSamples()
        XCTAssertEqual(restored, awkward)
    }

    func testMissingManifestFailsCleanly() {
        XCTAssertThrowsError(try CaptureReader(directory: tempDir))
    }
}
