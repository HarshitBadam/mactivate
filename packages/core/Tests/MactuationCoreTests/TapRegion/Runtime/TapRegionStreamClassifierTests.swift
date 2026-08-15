import Foundation
import XCTest
@testable import MactuationCore

final class TapRegionStreamClassifierTests: XCTestCase {
    func testStreamRejectsNonMonotonicGyroAndBoundsHistory() throws {
        let classifier = try TapRegionStreamClassifier(bufferDurationS: 1)
        for index in 0...1_600 {
            try classifier.append(.imu(
                path: .spuGyroscope,
                sample: IMUSample(
                    timestamp: Double(index) / 800,
                    x: 0,
                    y: 0,
                    z: 0
                )
            ))
        }

        XCTAssertLessThanOrEqual(classifier.bufferedGyroscopeSampleCount, 801)
        XCTAssertThrowsError(try classifier.append(.imu(
            path: .spuGyroscope,
            sample: IMUSample(timestamp: 1, x: 0, y: 0, z: 0)
        )))
    }

    func testStreamClassifierUsesMedianMembersAndRejectsMissingGyro() throws {
        let classifier = try TapRegionStreamClassifier()
        let peaks = [1.0, 1.3, 1.6]
        for index in 0...1_600 {
            let time = Double(index) / 800
            let relative = peaks.map { time - $0 }
            let x: Double
            if relative.contains(where: { $0 >= -0.02 && $0 < 0 }) {
                x = -4
            } else if relative.contains(where: { $0 >= 0 && $0 <= 0.02 }) {
                x = 1
            } else {
                x = 0
            }
            try classifier.append(.imu(
                path: .spuGyroscope,
                sample: IMUSample(timestamp: time, x: x, y: 0, z: 0)
            ))
        }
        let group = TapGroup(
            members: peaks.map {
                TapEventFeatures(
                    time: $0,
                    peakG: 0.1,
                    decayMs: 20,
                    zImpulseMgS: 0.1,
                    lateralImpulseMgS: 0.1
                )
            },
            verdict: .acceptedComfort
        )
        let profile = TapRegionCalibrationProfile(
            version: "personal-region-test",
            lowerBoundary: -1,
            upperBoundary: 1,
            lowerSide: .left,
            samplesPerGesture: 5
        )

        let result = classifier.classify(group: group, profile: profile)
        let emptyResult = try TapRegionStreamClassifier().classify(
            group: group,
            profile: profile
        )

        XCTAssertEqual(result.prediction, .left)
        XCTAssertEqual(result.reason, .resolved)
        XCTAssertEqual(result.memberFeatures.count, 3)
        XCTAssertEqual(emptyResult.prediction, .unknown)
        XCTAssertEqual(emptyResult.reason, .insufficientGyroscopeData)
    }
}
