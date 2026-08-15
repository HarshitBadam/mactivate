import MactuationCore
import XCTest
@testable import MactivateRuntime

final class TapCalibrationDraftTests: XCTestCase {
    func testOnlyAcceptedSinglesCountAndTargetCapsAtFive() throws {
        var draft = TapCalibrationDraft()

        XCTAssertThrowsError(try draft.record(
            feedback(
                outcome: .rejected(.comfortZImpulse),
                acceptanceVerdict: .rejected,
                memberCount: 1
            ),
            side: .left,
            intensity: .comfort
        )) {
            XCTAssertEqual(
                $0 as? TapCalibrationRecordError,
                .rejected(.comfortZImpulse)
            )
        }
        XCTAssertThrowsError(try draft.record(
            feedback(
                outcome: .acceptedNonActionable(.double),
                acceptanceVerdict: .acceptedComfort,
                memberCount: 2
            ),
            side: .left,
            intensity: .comfort
        ))

        for _ in 0..<6 {
            try draft.record(
                feedback(
                    outcome: .acceptedNonActionable(.single),
                    acceptanceVerdict: .acceptedComfort,
                    memberCount: 1
                ),
                side: .left,
                intensity: .comfort
            )
        }

        XCTAssertEqual(
            draft.sampleCount(side: .left, intensity: .comfort),
            TapCalibrationDraft.requiredSamplesPerTarget
        )
    }

    func testFirmCanLearnBelowExistingCutButFirmDoesNotFillComfort()
        throws {
        var draft = TapCalibrationDraft()
        let belowCutFirm = feedback(
            outcome: .rejected(.comfortZImpulse),
            acceptanceVerdict: .rejected,
            memberCount: 1
        )

        try draft.record(
            belowCutFirm,
            side: .right,
            intensity: .firm
        )
        XCTAssertEqual(
            draft.sampleCount(side: .right, intensity: .firm),
            1
        )

        XCTAssertThrowsError(try draft.record(
            feedback(
                outcome: .acceptedNonActionable(.single),
                acceptanceVerdict: .acceptedFirm(.left),
                memberCount: 1
            ),
            side: .left,
            intensity: .comfort
        )) {
            XCTAssertEqual(
                $0 as? TapCalibrationRecordError,
                .wrongIntensity(expected: .comfort)
            )
        }
        XCTAssertEqual(
            draft.sampleCount(side: .left, intensity: .comfort),
            0
        )
    }

    private func feedback(
        outcome: TapFeedbackOutcome,
        acceptanceVerdict: TapVerdict,
        memberCount: Int
    ) -> TapFeedback {
        TapFeedback(
            outcome: outcome,
            acceptanceVerdict: acceptanceVerdict,
            memberCount: memberCount,
            features: TapEventFeatures(
                time: 1,
                peakG: 0.1,
                decayMs: 20,
                zImpulseMgS: 0.2,
                lateralImpulseMgS: 0.1
            ),
            sensorTimestamp: 1,
            resolutionLatencyS: 0.6
        )
    }
}
