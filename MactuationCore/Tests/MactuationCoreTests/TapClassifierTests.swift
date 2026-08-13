import XCTest
@testable import MactuationCore

/// Hardware-independent classifier logic tests on synthetic streams.
/// These exercise the rule's plumbing only — capability claims live in the
/// capture-fixture tests, which score real recorded data.
final class TapClassifierTests: XCTestCase {
    private let rate = 800.0
    private let classifier = TapClassifier(calibration: .mac14_2Discovery)

    /// Flat gravity baseline with optional per-axis pulses injected.
    /// Each pulse adds `amplitude * exp(-dt/0.005)` for 25 ms from its onset.
    private func makeSamples(duration: Double,
                             pulses: [(time: Double, axis: Int, amplitude: Double)]) -> [IMUSample] {
        (0..<Int(duration * rate)).map { index in
            let t = Double(index) / rate
            var axes = [0.02, -0.01, -1.0]
            for pulse in pulses {
                let dt = t - pulse.time
                if dt >= 0 && dt < 0.025 {
                    axes[pulse.axis] += pulse.amplitude * exp(-dt / 0.005)
                }
            }
            return IMUSample(timestamp: t, x: axes[0], y: axes[1], z: axes[2])
        }
    }

    func testPositiveZPulseAcceptsAsComfortSingle() {
        let groups = classifier.classify(imuSamples: makeSamples(
            duration: 4, pulses: [(time: 2.0, axis: 2, amplitude: 0.08)]))
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].verdict, .acceptedComfort)
        XCTAssertEqual(groups[0].members.count, 1)
    }

    func testTripleWithinWindowGroupsAndAccepts() {
        let groups = classifier.classify(imuSamples: makeSamples(
            duration: 5, pulses: [(time: 2.0, axis: 2, amplitude: 0.08),
                                  (time: 2.4, axis: 2, amplitude: 0.08),
                                  (time: 2.8, axis: 2, amplitude: 0.08)]))
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].members.count, 3)
        XCTAssertEqual(groups[0].verdict, .acceptedComfort)
    }

    func testFourMemberGroupIsRejected() {
        let groups = classifier.classify(imuSamples: makeSamples(
            duration: 6, pulses: [(time: 2.0, axis: 2, amplitude: 0.08),
                                  (time: 2.4, axis: 2, amplitude: 0.08),
                                  (time: 2.8, axis: 2, amplitude: 0.08),
                                  (time: 3.2, axis: 2, amplitude: 0.08)]))
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].members.count, 4)
        XCTAssertEqual(groups[0].verdict, .rejected)
    }

    func testLateralImpulseVetoRejectsBumpShapedEvent() {
        // Positive Z-impulse (would pass the Z-gate) but strong lateral content.
        let groups = classifier.classify(imuSamples: makeSamples(
            duration: 4, pulses: [(time: 2.0, axis: 2, amplitude: 0.08),
                                  (time: 2.0, axis: 0, amplitude: 0.06)]))
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].verdict, .rejected)
        XCTAssertGreaterThanOrEqual(groups[0].members[0].lateralImpulseMgS, 0.25)
    }

    func testNegativeZFirmPeakAcceptsViaLeftFirmTier() {
        // Firm-tap signature: big peak, negative Z-impulse, low lateral, fast decay.
        let groups = classifier.classify(imuSamples: makeSamples(
            duration: 4, pulses: [(time: 2.0, axis: 2, amplitude: -0.4)]))
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].verdict, .acceptedFirm(.left))
    }

    func testNegativeZBelowFirmCutIsRejected() {
        // Typing/trackpad signature: sub-firm peak with negative Z-impulse.
        let groups = classifier.classify(imuSamples: makeSamples(
            duration: 4, pulses: [(time: 2.0, axis: 2, amplitude: -0.08)]))
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].verdict, .rejected)
    }

    func testQuietStreamProducesNoGroups() {
        XCTAssertEqual(classifier.classify(imuSamples: makeSamples(duration: 3, pulses: [])), [])
    }

    func testClassificationIsByteIdenticalAcrossRunsAndConfigRoundTrip() throws {
        let samples = makeSamples(duration: 6, pulses: [(time: 1.0, axis: 2, amplitude: 0.08),
                                                        (time: 3.0, axis: 2, amplitude: -0.4),
                                                        (time: 5.0, axis: 0, amplitude: 0.06)])
        let first = classifier.classify(imuSamples: samples)
        let second = classifier.classify(imuSamples: samples)
        XCTAssertEqual(first, second)
        XCTAssertEqual(classifier.digest(of: first), classifier.digest(of: second))

        // The calibration must survive JSON round-trip and classify identically.
        let data = try JSONEncoder().encode(TapCalibration.mac14_2Discovery)
        let restored = try JSONDecoder().decode(TapCalibration.self, from: data)
        XCTAssertEqual(restored, TapCalibration.mac14_2Discovery)
        let third = TapClassifier(calibration: restored).classify(imuSamples: samples)
        XCTAssertEqual(classifier.digest(of: third), classifier.digest(of: first))
    }

    func testEventIDIsStableAndVersionScoped() {
        let samples = makeSamples(duration: 4, pulses: [(time: 2.0, axis: 2, amplitude: 0.08)])
        let group = classifier.classify(imuSamples: samples)[0]
        let id = group.eventID(calibrationVersion: classifier.calibration.version)
        XCTAssertEqual(id, group.eventID(calibrationVersion: classifier.calibration.version))
        XCTAssertTrue(id.hasPrefix("mac14_2-20260724-left-calibrated-1/"))
    }

    func testSensorSampleEntryPointFiltersToAccelerometer() {
        let imu = makeSamples(duration: 4, pulses: [(time: 2.0, axis: 2, amplitude: 0.08)])
        var mixed: [SensorSample] = imu.map { .imu(path: .spuAccelerometer, sample: $0) }
        mixed.append(.als(path: .spuAmbientLight, sample: ALSSample(timestamp: 1, lux: 100)))
        mixed.append(.imu(path: .spuGyroscope, sample: IMUSample(timestamp: 2, x: 9, y: 9, z: 9)))
        XCTAssertEqual(classifier.classify(samples: mixed),
                       classifier.classify(imuSamples: imu))
    }

    func testPersonalCalibrationUsesAdaptiveThresholdForLaterMembers() {
        var calibration = TapCalibration.mac14_2Discovery
        calibration.version = "personal-test"
        let personal = TapClassifier(calibration: calibration)
        let samples = makeSamples(
            duration: 5,
            pulses: [
                (time: 2.0, axis: 2, amplitude: 0.08),
                (time: 2.4, axis: 2, amplitude: 0.03)
            ]
        )

        let groups = personal.classify(imuSamples: samples)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].members.count, 2)
        XCTAssertTrue(groups[0].verdict.isAccepted)
    }

    func testPersonalCalibrationSuppressesFirmTapAftershock() {
        var calibration = TapCalibration.mac14_2Discovery
        calibration.version = "personal-test"
        let personal = TapClassifier(calibration: calibration)
        let samples = makeSamples(
            duration: 5,
            pulses: [
                (time: 2.0, axis: 2, amplitude: -0.4),
                (time: 2.18, axis: 2, amplitude: -0.10)
            ]
        )

        let groups = personal.classify(imuSamples: samples)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].members.count, 1)
        XCTAssertTrue(groups[0].verdict.isAccepted)
    }
}
