import MactuationCore
import MactivateRuntime
import XCTest
@testable import MactivateApp

@MainActor
final class CalibrationFlowTests: XCTestCase {
    func testTapCalibrationRetriesRejectedSamplesAndStopsAtFive() {
        let runtime = FakeRuntime()
        let coordinator = makeCoordinator(runtime: runtime)
        let target = TapCalibrationTarget(side: .left, intensity: .comfort)
        coordinator.state.tapCalibrationTarget = target

        runtime.outputHandler?(.tapFeedback(calibrationFeedback(
            outcome: .rejected(.comfortZImpulse),
            zImpulseMgS: -0.2
        )))

        XCTAssertEqual(
            coordinator.state.tapCalibrationDraft.sampleCount(
                side: .left,
                intensity: .comfort
            ),
            0
        )
        XCTAssertNotNil(coordinator.state.tapCalibrationError)

        for _ in 0..<TapCalibrationDraft.requiredSamplesPerTarget {
            runtime.outputHandler?(.tapFeedback(calibrationFeedback(
                outcome: .acceptedNonActionable(.single),
                zImpulseMgS: 0.2
            )))
        }

        XCTAssertEqual(
            coordinator.state.tapCalibrationDraft.sampleCount(
                side: .left,
                intensity: .comfort
            ),
            TapCalibrationDraft.requiredSamplesPerTarget
        )
        XCTAssertNil(coordinator.state.tapCalibrationTarget)
        XCTAssertNil(coordinator.state.tapCalibrationError)
    }

    func testRegionCalibrationAdvancesTargetsAndSavesQualifiedProfile() {
        let runtime = FakeRuntime()
        let coordinator = makeCoordinator(runtime: runtime)
        coordinator.state.tapRegionCalibrationTarget =
            TapRegionCalibrationTarget.ordered.first

        for index in 0..<20 {
            guard let target =
                    coordinator.state.tapRegionCalibrationTarget else {
                return XCTFail("calibration ended before 20 gestures")
            }
            let base = target.side == .left ? -3.0 : 3.0
            let memberFeatures = (0..<target.pattern.memberCount).map {
                base + Double(index % 5) * 0.01 + Double($0) * 0.02
            }
            runtime.outputHandler?(.tapFeedback(TapFeedback(
                outcome: index == 19
                    ? .dispatched(
                        gesture: PalmTapGesture(
                            side: target.side,
                            pattern: target.pattern
                        ),
                        action: "calibration.action"
                    )
                    : .spatialUnavailable(
                        pattern: target.pattern,
                        reason: .calibrationRequired
                    ),
                memberCount: target.pattern.memberCount,
                features: TapEventFeatures(
                    time: Double(index),
                    peakG: 0.1,
                    decayMs: 20,
                    zImpulseMgS: 0.1,
                    lateralImpulseMgS: 0.1
                ),
                sensorTimestamp: Double(index),
                resolutionLatencyS: 1,
                regionPrediction: .unknown,
                regionMemberFeatures: memberFeatures,
                regionFeature: memberFeatures.reduce(0, +) /
                    Double(memberFeatures.count),
                regionReason: .ambiguous
            )))
        }
        runtime.outputHandler?(.intent(.performAction(
            id: "calibration.action",
            trigger: TapTrigger(
                eventID: RuntimeEventID(
                    sessionID: UUID(),
                    classifierEventID: "final-calibration-gesture"
                ),
                gesture: .rightTriple,
                sensorTimestamp: 20,
                regionProfileVersion: "personal-region-old"
            )
        )))

        XCTAssertNil(coordinator.state.tapRegionCalibrationTarget)
        XCTAssertTrue(
            coordinator.state.tapRegionCalibrationProfile?.isValid == true
        )
        XCTAssertEqual(
            runtime.currentTapRegionCalibrationProfile,
            coordinator.state.tapRegionCalibrationProfile
        )
        XCTAssertNil(coordinator.state.actionError)
    }
}
