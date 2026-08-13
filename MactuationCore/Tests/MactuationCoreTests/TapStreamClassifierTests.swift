import XCTest
@testable import MactuationCore

final class TapStreamClassifierTests: XCTestCase {
    private let rate = 800.0
    private let calibration = TapCalibration.mac14_2Discovery

    private func makeSamples(
        duration: Double,
        pulses: [(time: Double, x: Double, y: Double, z: Double)]
    ) -> [IMUSample] {
        (0..<Int(duration * rate)).map { index in
            let time = Double(index) / rate
            var axes = [0.02, -0.01, -1.0]
            for pulse in pulses {
                let delta = time - pulse.time
                if delta >= 0, delta < 0.025 {
                    let decay = exp(-delta / 0.005)
                    axes[0] += pulse.x * decay
                    axes[1] += pulse.y * decay
                    axes[2] += pulse.z * decay
                }
            }
            return IMUSample(
                timestamp: time,
                x: axes[0],
                y: axes[1],
                z: axes[2]
            )
        }
    }

    private func replay(_ samples: [IMUSample],
                        finish: Bool = true) throws -> (
                            classifier: TapStreamClassifier,
                            groups: [TapGroup]
                        ) {
        let stream = try TapStreamClassifier(
            calibration: calibration,
            sampleRateHz: rate
        )
        var groups: [TapGroup] = []
        for sample in samples {
            groups.append(contentsOf: try stream.append(sample))
        }
        if finish {
            groups.append(contentsOf: stream.finishForReplay())
        }
        return (stream, groups)
    }

    func testResolvedGroupsMatchBatchVerdictsAndStableIDs() throws {
        let samples = makeSamples(
            duration: 7,
            pulses: [
                (time: 1.0, x: 0, y: 0, z: 0.08),
                (time: 3.0, x: 0, y: 0, z: 0.08),
                (time: 3.4, x: 0, y: 0, z: 0.08),
                (time: 5.0, x: 0.06, y: 0, z: 0.08)
            ]
        )
        let batch = TapClassifier(calibration: calibration).classify(
            imuSamples: samples,
            sampleRateHz: rate
        )
        let streamed = try replay(samples).groups

        XCTAssertEqual(streamed.map(\.verdict), batch.map(\.verdict))
        XCTAssertEqual(streamed.map { $0.members.count }, batch.map { $0.members.count })
        XCTAssertEqual(
            streamed.map { $0.eventID(calibrationVersion: calibration.version) },
            batch.map { $0.eventID(calibrationVersion: calibration.version) }
        )
    }

    func testGroupWaitsForLookaheadTailAndFullGroupingGap() throws {
        let samples = makeSamples(
            duration: 3.6,
            pulses: [(time: 2.0, x: 0, y: 0, z: 0.08)]
        )
        let stream = try TapStreamClassifier(
            calibration: calibration,
            sampleRateHz: rate
        )
        var groups: [TapGroup] = []
        for sample in samples where sample.timestamp < 3.1 {
            groups.append(contentsOf: try stream.append(sample))
        }
        XCTAssertTrue(groups.isEmpty)

        var emittedAt: SensorTimestamp?
        for sample in samples where sample.timestamp >= 3.1 {
            let resolved = try stream.append(sample)
            if !resolved.isEmpty, emittedAt == nil { emittedAt = sample.timestamp }
            groups.append(contentsOf: resolved)
        }
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].verdict, .acceptedComfort)
        XCTAssertGreaterThanOrEqual(
            stream.lastResolvedThrough ?? 0,
            groups[0].members[0].time + calibration.groupGapS
        )
        let latency = try XCTUnwrap(emittedAt) - groups[0].members[0].time
        XCTAssertGreaterThanOrEqual(latency, 1.2)
        XCTAssertLessThan(latency, 1.5)
    }

    func testCandidateFeedbackPrecedesFinalTapCount() throws {
        let samples = makeSamples(
            duration: 3.6,
            pulses: [(time: 2.0, x: 0, y: 0, z: 0.08)]
        )
        let stream = try TapStreamClassifier(
            calibration: calibration,
            sampleRateHz: rate
        )
        var candidateAt: SensorTimestamp?
        var resolvedAt: SensorTimestamp?

        for sample in samples {
            let update = try stream.appendWithFeedback(sample)
            if !update.candidates.isEmpty, candidateAt == nil {
                candidateAt = sample.timestamp
            }
            if !update.resolvedGroups.isEmpty, resolvedAt == nil {
                resolvedAt = sample.timestamp
            }
        }

        let candidate = try XCTUnwrap(candidateAt)
        let resolved = try XCTUnwrap(resolvedAt)
        XCTAssertLessThan(candidate - 2.0, 0.6)
        XCTAssertGreaterThan(resolved - candidate, 0.7)
    }

    func testOverlappingWindowsEmitEachGroupOnceAndStayBounded() throws {
        let samples = makeSamples(
            duration: 12,
            pulses: (1...10).map {
                (time: Double($0), x: 0.0, y: 0.0, z: 0.08)
            }
        )
        let result = try replay(samples)

        let identifiers = result.groups.map {
            $0.eventID(calibrationVersion: calibration.version)
        }
        XCTAssertEqual(identifiers.count, Set(identifiers).count)
        XCTAssertLessThanOrEqual(
            result.classifier.bufferedSampleCount,
            Int(4 * rate) + 2
        )
    }

    func testResetDiscardsUnresolvedGroupAndRestoresConfiguredRate() throws {
        let samples = makeSamples(
            duration: 2.5,
            pulses: [(time: 2.0, x: 0, y: 0, z: 0.08)]
        )
        let stream = try TapStreamClassifier(
            calibration: calibration,
            sampleRateHz: rate
        )
        for sample in samples {
            _ = try stream.append(sample)
        }

        stream.reset()

        XCTAssertEqual(stream.bufferedSampleCount, 0)
        XCTAssertEqual(stream.sampleRateHz, rate)
        XCTAssertTrue(stream.finishForReplay().isEmpty)
    }

    func testFiniteReplayFinalizationIsExplicit() throws {
        let samples = makeSamples(
            duration: 2.4,
            pulses: [(time: 2.0, x: 0, y: 0, z: 0.08)]
        )
        let result = try replay(samples, finish: false)

        XCTAssertTrue(result.groups.isEmpty)
        XCTAssertEqual(result.classifier.finishForReplay().count, 1)
        XCTAssertTrue(result.classifier.finishForReplay().isEmpty)
    }

    func testRejectsBackwardsTimestampAndIgnoresOtherPaths() throws {
        let stream = try TapStreamClassifier(sampleRateHz: rate)
        XCTAssertTrue(try stream.append(.als(
            path: .spuAmbientLight,
            sample: ALSSample(timestamp: 1, lux: 100)
        )).isEmpty)
        _ = try stream.append(IMUSample(timestamp: 1, x: 0, y: 0, z: -1))
        XCTAssertThrowsError(
            try stream.append(IMUSample(timestamp: 0.9, x: 0, y: 0, z: -1))
        ) {
            XCTAssertEqual(
                $0 as? TapStreamError,
                .nonMonotonicTimestamp(previous: 1, current: 0.9)
            )
        }
    }

    func testFreezesMeasuredRateAfterWarmupWithTimestampJitter() throws {
        let stream = try TapStreamClassifier()
        var time = 0.0
        for index in 0..<900 {
            time += 1 / rate + (index.isMultiple(of: 2) ? 0.00001 : -0.00001)
            _ = try stream.append(IMUSample(timestamp: time, x: 0, y: 0, z: -1))
        }

        let frozen = try XCTUnwrap(stream.sampleRateHz)
        XCTAssertEqual(frozen, rate, accuracy: 1)
        for index in 0..<100 {
            time += 1 / rate + (index.isMultiple(of: 2) ? 0.0001 : -0.0001)
            _ = try stream.append(IMUSample(timestamp: time, x: 0, y: 0, z: -1))
        }
        XCTAssertEqual(stream.sampleRateHz, frozen)
    }

    func testInvalidConfigurationIsRejected() {
        XCTAssertThrowsError(
            try TapStreamClassifier(
                configuration: TapStreamConfiguration(bufferDurationS: 1)
            )
        )
        XCTAssertThrowsError(try TapStreamClassifier(sampleRateHz: 0))
    }
}
