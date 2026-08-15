import Foundation
import XCTest
@testable import MactuationCore

final class TapRegionFeatureExtractorTests: XCTestCase {
    func testFeatureExtractorComputesBaselineCorrectedPeakBalance() throws {
        let samples = stride(from: 0.70, through: 1.10, by: 0.00125).map {
            time -> IMUSample in
            let x: Double
            if time >= 0.98 && time < 1.0 {
                x = -4
            } else if time >= 1.0 && time <= 1.02 {
                x = 1
            } else {
                x = 0
            }
            return IMUSample(timestamp: time, x: x, y: 0, z: 0)
        }

        let feature = try TapRegionFeatureExtractor().extract(
            gyroscope: samples,
            peakTimestamp: 1.0
        )

        XCTAssertEqual(feature.gyroXPeakBalanceDegS, -3, accuracy: 1e-9)
    }

    func testFeatureExtractorRequiresPostEventWindowAndTightSync() {
        let baselineAndEarlyWindow = stride(
            from: 0.70,
            through: 1.02,
            by: 0.00125
        ).map {
            IMUSample(timestamp: $0, x: 0, y: 0, z: 0)
        }

        XCTAssertThrowsError(
            try TapRegionFeatureExtractor().extract(
                gyroscope: baselineAndEarlyWindow,
                peakTimestamp: 1
            )
        ) {
            XCTAssertEqual(
                $0 as? TapRegionFeatureExtractionError,
                .insufficientPostEventData
            )
        }
    }

    func testFeatureExtractorRejectsSparseGyroscopeWindow() {
        let baseline = stride(
            from: 0.75,
            through: 0.92,
            by: 0.00125
        ).map {
            IMUSample(timestamp: $0, x: 0, y: 0, z: 0)
        }
        let sparseWindow = [0.95, 1.0, 1.05].map {
            IMUSample(timestamp: $0, x: 0, y: 0, z: 0)
        }

        XCTAssertThrowsError(
            try TapRegionFeatureExtractor().extract(
                gyroscope: baseline + sparseWindow,
                peakTimestamp: 1
            )
        ) {
            XCTAssertEqual(
                $0 as? TapRegionFeatureExtractionError,
                .discontinuousGyroscopeData
            )
        }
    }
}
