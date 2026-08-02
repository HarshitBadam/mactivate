import XCTest
@testable import MactuationCore

final class DeterminismTests: XCTestCase {
    private final class DeliveryState: @unchecked Sendable {
        private let lock = NSLock()
        private var samples: [SensorSample] = []
        private var deliveredOnMainThread = false

        func append(_ sample: SensorSample) {
            lock.lock()
            samples.append(sample)
            deliveredOnMainThread = deliveredOnMainThread || Thread.isMainThread
            lock.unlock()
        }

        func snapshot() -> (samples: [SensorSample], deliveredOnMainThread: Bool) {
            lock.lock()
            defer { lock.unlock() }
            return (samples, deliveredOnMainThread)
        }
    }

    func testMockIsDeterministicPerSeed() {
        let config = MockSensorSource.Configuration(seed: 7, duration: 3,
                                                    taps: [(time: 1.0, amplitude: 0.02)])
        let a = StreamDigest.digest(of: MockSensorSource(configuration: config).generate())
        let b = StreamDigest.digest(of: MockSensorSource(configuration: config).generate())
        XCTAssertEqual(a, b)

        var other = config
        other.seed = 8
        let c = StreamDigest.digest(of: MockSensorSource(configuration: other).generate())
        XCTAssertNotEqual(a, c)
    }

    func testReplayDeliversIdenticalSequenceTwice() throws {
        let samples = MockSensorSource(configuration: .init(seed: 3, duration: 2)).generate()

        func replayDigest() throws -> String {
            var digest = StreamDigest()
            let source = ReplaySensorSource(samples: samples)
            try source.start { digest.update($0) }
            source.stop()
            return digest.value
        }

        let first = try replayDigest()
        let second = try replayDigest()
        XCTAssertEqual(first, second)
        XCTAssertEqual(first, StreamDigest.digest(of: samples))
    }

    func testWrittenCaptureReplaysToSameDigest() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mactuation-digest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let samples = MockSensorSource(configuration: .init(
            seed: 11, duration: 2, taps: [(time: 0.4, amplitude: 0.05)],
            covers: [(start: 1.2, end: 1.4)])).generate()
        let originalDigest = StreamDigest.digest(of: samples)

        let writer = try CaptureWriter(
            directory: tempDir,
            manifest: SessionManifest(label: "digest", startedAt: Date(), toolVersion: "test-0"))
        for sample in samples {
            try writer.append(sample)
        }
        try writer.finalize()

        var replayed = StreamDigest()
        let source = try ReplaySensorSource(reader: CaptureReader(directory: tempDir))
        try source.start { replayed.update($0) }
        XCTAssertEqual(replayed.value, originalDigest)
    }

    func testEqualTimestampAndPathPreserveInputOrder() throws {
        let samples: [SensorSample] = [
            .imu(path: .spuAccelerometer, sample: IMUSample(timestamp: 1, x: 1, y: 0, z: 0)),
            .imu(path: .spuAccelerometer, sample: IMUSample(timestamp: 1, x: 2, y: 0, z: 0)),
            .imu(path: .spuAccelerometer, sample: IMUSample(timestamp: 1, x: 3, y: 0, z: 0))
        ]
        let replay = ReplaySensorSource(samples: samples)
        var replayed: [SensorSample] = []
        try replay.start { replayed.append($0) }
        XCTAssertEqual(replayed, samples)

        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mactuation-order-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let writer = try CaptureWriter(
            directory: tempDir,
            manifest: SessionManifest(label: "order", startedAt: Date(), toolVersion: "test-0"))
        for sample in samples {
            try writer.append(sample)
        }
        try writer.finalize()

        XCTAssertEqual(try CaptureReader(directory: tempDir).mergedSamples(), samples)
    }

    func testStartTwiceIsRejected() throws {
        let source = ReplaySensorSource(samples: [])
        try source.start { _ in }
        XCTAssertThrowsError(try source.start { _ in }) {
            XCTAssertEqual($0 as? SensorSourceError, .alreadyStarted)
        }
    }

    func testProcessingQueueDeliversInOrderOffMainThread() {
        let queue = SensorProcessingQueue()
        let samples = MockSensorSource(configuration: .init(seed: 4, duration: 0.02)).generate()
        let state = DeliveryState()

        for sample in samples {
            queue.submit(sample) {
                state.append($0)
            }
        }
        queue.finish()

        let result = state.snapshot()
        XCTAssertEqual(result.samples, samples)
        XCTAssertFalse(result.deliveredOnMainThread)
    }
}
