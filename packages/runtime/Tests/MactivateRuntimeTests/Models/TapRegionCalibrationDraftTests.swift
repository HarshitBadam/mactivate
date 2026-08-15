import MactuationCore
import XCTest
@testable import MactivateRuntime

final class TapRegionCalibrationDraftTests: XCTestCase {
    func testDraftRequiresExactResolvedCountAndGyroFeatures() {
        var draft = TapRegionCalibrationDraft()
        let target = TapRegionCalibrationTarget(
            side: .left,
            pattern: .double
        )

        XCTAssertThrowsError(
            try draft.record(
                feedback(memberFeatures: [-3, -3, -3]),
                target: target
            )
        ) {
            XCTAssertEqual(
                $0 as? TapRegionCalibrationRecordError,
                .wrongTapCount(expected: 2, detected: 3)
            )
        }
        XCTAssertEqual(draft.totalSampleCount, 0)
    }

    func testTwentyUserPacedGesturesBuildQualifiedProfile() throws {
        var draft = TapRegionCalibrationDraft()
        for target in TapRegionCalibrationTarget.ordered {
            for repetition in 1...5 {
                let base = target.side == .left ? -3.0 : 3.0
                let values = (0..<target.pattern.memberCount).map {
                    base + Double(repetition) * 0.01 + Double($0) * 0.02
                }
                try draft.record(
                    feedback(memberFeatures: values),
                    target: target
                )
            }
        }

        let result = try draft.buildProfile()

        XCTAssertTrue(draft.isComplete)
        XCTAssertEqual(draft.totalSampleCount, 20)
        XCTAssertTrue(result.profile.isValid)
        XCTAssertTrue(result.crossValidationMetrics.qualifies)
    }

    private func feedback(memberFeatures: [Double]) -> TapFeedback {
        TapFeedback(
            outcome: .spatialUnavailable(
                pattern: memberFeatures.count == 2 ? .double : .triple,
                reason: .calibrationRequired
            ),
            memberCount: memberFeatures.count,
            features: TapEventFeatures(
                time: 1,
                peakG: 0.1,
                decayMs: 20,
                zImpulseMgS: 0.1,
                lateralImpulseMgS: 0.1
            ),
            sensorTimestamp: 1,
            resolutionLatencyS: 1,
            regionPrediction: .unknown,
            regionMemberFeatures: memberFeatures,
            regionFeature: memberFeatures.reduce(0, +) /
                Double(memberFeatures.count),
            regionReason: .ambiguous
        )
    }
}
