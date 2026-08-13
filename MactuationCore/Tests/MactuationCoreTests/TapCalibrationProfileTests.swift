import XCTest
@testable import MactuationCore

final class TapCalibrationProfileTests: XCTestCase {
    func testBuildsIndependentSidesAndRoundTrips() throws {
        let profile = try TapCalibrationProfileBuilder.build(
            comfort: [
                .left: features(peak: 0.08, z: 0.4),
                .right: features(peak: 0.06, z: 0.3)
            ],
            firm: [
                .left: features(peak: 0.30, z: -0.2),
                .right: features(peak: 0.18, z: -0.1)
            ]
        )

        XCTAssertTrue(profile.isValid)
        XCTAssertEqual(profile.sideSummaries[.left]?.comfortSampleCount, 5)
        XCTAssertEqual(profile.sideSummaries[.right]?.firmSampleCount, 5)
        XCTAssertNotEqual(
            profile.calibration.firmTiers[.left]?.amplitudeCutG,
            profile.calibration.firmTiers[.right]?.amplitudeCutG
        )

        let restored = try JSONDecoder().decode(
            TapCalibrationProfile.self,
            from: JSONEncoder().encode(profile)
        )
        XCTAssertEqual(restored, profile)
    }

    func testRequiresBothForceLevelsOnBothSides() {
        XCTAssertThrowsError(try TapCalibrationProfileBuilder.build(
            comfort: [
                .left: features(peak: 0.08, z: 0.4),
                .right: features(peak: 0.06, z: 0.3)
            ],
            firm: [
                .left: features(peak: 0.30, z: -0.2)
            ]
        )) { error in
            XCTAssertEqual(
                error as? TapCalibrationProfileError,
                .insufficientSamples(side: .right, force: .firm)
            )
        }
    }

    private func features(
        peak: Double,
        z: Double
    ) -> [TapEventFeatures] {
        (0..<5).map { index in
            TapEventFeatures(
                time: Double(index),
                peakG: peak + Double(index) * 0.001,
                decayMs: 50,
                zImpulseMgS: z,
                lateralImpulseMgS: 0.1
            )
        }
    }
}
