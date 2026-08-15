import Foundation
import XCTest
@testable import MactuationCore

final class TapRegionCalibrationTests: XCTestCase {
    func testProfileUsesGuardBandAndFailsClosedWhenInvalid() {
        let profile = TapRegionCalibrationProfile(
            version: "personal-region-test",
            lowerBoundary: -1,
            upperBoundary: 1,
            lowerSide: .left,
            samplesPerGesture: 5
        )

        XCTAssertEqual(profile.predict(feature: -2), .left)
        XCTAssertEqual(profile.predict(feature: 2), .right)
        XCTAssertEqual(profile.predict(feature: 0), .unknown)

        var invalid = profile
        invalid.schemaVersion += 1
        XCTAssertEqual(invalid.predict(feature: -2), .unknown)
    }

    func testProfileCodableRoundTripPreservesDeterministicDigest() throws {
        let profile = TapRegionCalibrationProfile(
            version: "personal-region-codable",
            lowerBoundary: -1.25,
            upperBoundary: 0.75,
            lowerSide: .right,
            samplesPerGesture: 5
        )

        let decoded = try JSONDecoder().decode(
            TapRegionCalibrationProfile.self,
            from: JSONEncoder().encode(profile)
        )

        XCTAssertEqual(decoded, profile)
        XCTAssertEqual(decoded.deterministicDigest, profile.deterministicDigest)
    }

    func testCalibrationBuilderQualifiesSeparatedGestureDistributions() throws {
        let gestures = calibrationGestures()

        let result = try TapRegionCalibrationProfileBuilder.build(
            gestures: gestures,
            version: "personal-region-test"
        )

        XCTAssertTrue(result.profile.isValid)
        XCTAssertTrue(result.crossValidationMetrics.qualifies)
        XCTAssertEqual(result.profile.predict(feature: -2), .left)
        XCTAssertEqual(result.profile.predict(feature: 2), .right)
        XCTAssertLessThan(result.profile.lowerBoundary, result.profile.upperBoundary)
    }

    func testCalibrationBuilderRejectsOverlappingSides() {
        var gestures = calibrationGestures()
        gestures = gestures.map {
            var copy = $0
            copy.memberFeatures = Array(
                repeating: 0.1,
                count: copy.pattern.memberCount
            )
            return copy
        }

        XCTAssertThrowsError(
            try TapRegionCalibrationProfileBuilder.build(
                gestures: gestures,
                version: "personal-region-test"
            )
        ) {
            XCTAssertEqual(
                $0 as? TapRegionCalibrationProfileError,
                .overlappingDistributions
            )
        }
    }

    private func calibrationGestures() -> [TapRegionCalibrationGesture] {
        var gestures: [TapRegionCalibrationGesture] = []
        for repetition in 1...5 {
            for pattern in TapRegionPattern.allCases {
                for side in TapRegionSide.allCases {
                    let base = side == .left ? -3.0 : 3.0
                    let values = (0..<pattern.memberCount).map {
                        base + Double(repetition) * 0.02 + Double($0) * 0.01
                    }
                    gestures.append(TapRegionCalibrationGesture(
                        side: side,
                        pattern: pattern,
                        repetition: repetition,
                        memberFeatures: values
                    ))
                }
            }
        }
        return gestures
    }
}
