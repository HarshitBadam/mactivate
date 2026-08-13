import XCTest
@testable import MactuationCore

final class AmbientLightDipDetectorTests: XCTestCase {
    private var calibration: AmbientLightDipCalibration {
        AmbientLightDipCalibration(
            version: "test-1",
            warmupSampleCount: 3,
            minimumBaselineLux: 30,
            floorLux: 1.5,
            floorConfirmationS: 1,
            minimumAbsoluteDropLux: 5,
            minimumRelativeDrop: 0.20,
            recoveryFraction: 0.90,
            maximumDipS: 3,
            baselineSmoothingFactor: 0.02,
            cooldownS: 2
        )
    }

    private func warm(_ detector: AmbientLightDipDetector,
                      lux: Double = 100) throws -> [AmbientLightDipEvent] {
        var events: [AmbientLightDipEvent] = []
        for index in 0..<3 {
            events.append(contentsOf: try detector.process(
                ALSSample(timestamp: Double(index) * 0.1, lux: lux)
            ))
        }
        return events
    }

    func testWarmupBecomesAvailableAndEmitsOnePanelHint() throws {
        let detector = try AmbientLightDipDetector(calibration: calibration)
        XCTAssertEqual(try warm(detector), [.readinessChanged(.available)])

        let first = try detector.process(ALSSample(timestamp: 0.3, lux: 70))
        let repeated = try detector.process(ALSSample(timestamp: 0.4, lux: 60))

        guard case .panelOpenHint(let hint)? = first.first else {
            return XCTFail("expected panel-open hint")
        }
        XCTAssertEqual(hint.timestamp, 0.3)
        XCTAssertEqual(hint.baselineLux, 100)
        XCTAssertEqual(hint.observedLux, 70)
        XCTAssertEqual(hint.relativeDrop, 0.3, accuracy: 0.000_001)
        XCTAssertTrue(repeated.isEmpty)
    }

    func testBothAbsoluteAndRelativeDropGatesMustPass() throws {
        var strictAbsolute = calibration
        strictAbsolute.minimumAbsoluteDropLux = 30
        let detector = try AmbientLightDipDetector(calibration: strictAbsolute)
        _ = try warm(detector)

        XCTAssertTrue(
            try detector.process(ALSSample(timestamp: 0.3, lux: 75)).isEmpty
        )
    }

    func testRecoveryAndCooldownSuppressRepeatedHints() throws {
        let detector = try AmbientLightDipDetector(calibration: calibration)
        _ = try warm(detector)
        XCTAssertEqual(
            try detector.process(ALSSample(timestamp: 0.3, lux: 70)).count,
            1
        )
        XCTAssertTrue(
            try detector.process(ALSSample(timestamp: 0.4, lux: 95)).isEmpty
        )
        XCTAssertTrue(
            try detector.process(ALSSample(timestamp: 1.0, lux: 60)).isEmpty
        )
        XCTAssertTrue(
            try detector.process(ALSSample(timestamp: 2.3, lux: 100)).isEmpty
        )
        XCTAssertEqual(
            try detector.process(ALSSample(timestamp: 2.5, lux: 60)).count,
            1
        )
    }

    func testDimWarmupAndRecoveryAreExplicit() throws {
        let detector = try AmbientLightDipDetector(calibration: calibration)
        XCTAssertEqual(
            try warm(detector, lux: 1),
            [.readinessChanged(.tooDim)]
        )
        XCTAssertEqual(detector.readiness, .tooDim)

        var events: [AmbientLightDipEvent] = []
        for index in 3..<6 {
            events.append(contentsOf: try detector.process(
                ALSSample(timestamp: Double(index) * 0.1, lux: 100)
            ))
        }
        XCTAssertEqual(events, [.readinessChanged(.available)])
    }

    func testSustainedFloorTransitionsToTooDim() throws {
        let detector = try AmbientLightDipDetector(calibration: calibration)
        _ = try warm(detector)
        _ = try detector.process(ALSSample(timestamp: 0.3, lux: 1))

        let events = try detector.process(ALSSample(timestamp: 1.3, lux: 1))

        XCTAssertEqual(events, [.readinessChanged(.tooDim)])
        XCTAssertEqual(detector.readiness, .tooDim)
    }

    func testPersistentLightingChangeReentersWarmupInsteadOfSticking() throws {
        let detector = try AmbientLightDipDetector(calibration: calibration)
        _ = try warm(detector)
        _ = try detector.process(ALSSample(timestamp: 0.3, lux: 60))

        let events = try detector.process(ALSSample(timestamp: 3.3, lux: 60))

        XCTAssertEqual(events, [.readinessChanged(.warmingUp)])
        XCTAssertEqual(detector.readiness, .warmingUp)
        XCTAssertNil(detector.baselineLux)
    }

    func testReplayIsDeterministic() throws {
        let samples = [
            ALSSample(timestamp: 0, lux: 100),
            ALSSample(timestamp: 0.1, lux: 101),
            ALSSample(timestamp: 0.2, lux: 99),
            ALSSample(timestamp: 0.3, lux: 70),
            ALSSample(timestamp: 0.4, lux: 95),
            ALSSample(timestamp: 2.5, lux: 100),
            ALSSample(timestamp: 2.6, lux: 60)
        ]
        func replay() throws -> [AmbientLightDipEvent] {
            let detector = try AmbientLightDipDetector(calibration: calibration)
            return try samples.flatMap { try detector.process($0) }
        }

        XCTAssertEqual(try replay(), try replay())
    }

    func testCalibrationRoundTripsAndResetRestoresWarmup() throws {
        let data = try JSONEncoder().encode(calibration)
        XCTAssertEqual(
            try JSONDecoder().decode(AmbientLightDipCalibration.self, from: data),
            calibration
        )
        let detector = try AmbientLightDipDetector(calibration: calibration)
        _ = try warm(detector)

        detector.reset()

        XCTAssertEqual(detector.readiness, .warmingUp)
        XCTAssertNil(detector.baselineLux)
    }

    func testInvalidInputAndConfigurationAreRejected() throws {
        var invalid = calibration
        invalid.minimumRelativeDrop = 1
        XCTAssertThrowsError(try AmbientLightDipDetector(calibration: invalid))

        let detector = try AmbientLightDipDetector(calibration: calibration)
        XCTAssertThrowsError(
            try detector.process(ALSSample(timestamp: 0, lux: .nan))
        )
        _ = try detector.process(ALSSample(timestamp: 1, lux: 100))
        XCTAssertThrowsError(
            try detector.process(ALSSample(timestamp: 0.5, lux: 100))
        )
    }

    func testOtherSensorPathsAreIgnored() throws {
        let detector = try AmbientLightDipDetector(calibration: calibration)
        XCTAssertTrue(try detector.process(.imu(
            path: .spuAccelerometer,
            sample: IMUSample(timestamp: 0, x: 0, y: 0, z: -1)
        )).isEmpty)
        XCTAssertEqual(detector.readiness, .warmingUp)
    }
}
