import Foundation
import MactuationCore
import XCTest
@testable import MactivateRuntime

final class TapRegionCalibrationProfileStoreTests: XCTestCase {
    func testRegionProfileRoundTripsIndependently() throws {
        let (defaults, key) = makeDefaults()
        let store = UserDefaultsTapRegionCalibrationProfileStore(
            defaults: defaults,
            key: key
        )
        let profile = validProfile()

        try store.save(profile)

        XCTAssertEqual(store.load(), .loaded(profile))
    }

    func testCorruptAndFutureProfilesArePreservedFailClosed() throws {
        let (defaults, key) = makeDefaults()
        let store = UserDefaultsTapRegionCalibrationProfileStore(
            defaults: defaults,
            key: key
        )
        let corrupt = Data("{broken".utf8)
        defaults.set(corrupt, forKey: key)

        guard case .invalid = store.load() else {
            return XCTFail("corrupt profile should fail closed")
        }
        XCTAssertEqual(defaults.data(forKey: key), corrupt)

        var future = validProfile()
        future.schemaVersion += 1
        let futureData = try JSONEncoder().encode(future)
        defaults.set(futureData, forKey: key)
        guard case .invalid = store.load() else {
            return XCTFail("future profile should fail closed")
        }
        XCTAssertEqual(defaults.data(forKey: key), futureData)
    }

    func testResetDoesNotChangeTapAcceptanceProfileKey() throws {
        let (defaults, key) = makeDefaults()
        let tapKey = "\(key).tap"
        let tapStore = UserDefaultsTapCalibrationProfileStore(
            defaults: defaults,
            key: tapKey
        )
        let regionStore = UserDefaultsTapRegionCalibrationProfileStore(
            defaults: defaults,
            key: key
        )
        var calibration = TapCalibration.mac14_2SpatialMultiTap
        calibration.version =
            "personal-spatial-region-store-independence"
        calibration.firmTiers[.right] = calibration.firmTiers[.left]
        let summary = TapCalibrationSideSummary(
            comfortSampleCount: 5,
            firmSampleCount: 5,
            comfortPeakMedianG: 0.1,
            firmPeakMedianG: 0.3,
            zImpulseMedianMgS: 0.1
        )
        let tapProfile = TapCalibrationProfile(
            calibration: calibration,
            sideSummaries: [.left: summary, .right: summary]
        )
        try tapStore.save(tapProfile)
        try regionStore.save(validProfile())

        regionStore.reset()

        XCTAssertEqual(tapStore.load(), .loaded(tapProfile))
        XCTAssertEqual(regionStore.load(), .missing)
    }

    private func validProfile() -> TapRegionCalibrationProfile {
        TapRegionCalibrationProfile(
            version: "personal-region-store-test",
            lowerBoundary: -1,
            upperBoundary: 1,
            lowerSide: .left,
            samplesPerGesture: 5
        )
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suite = "TapRegionStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (defaults, "region-profile")
    }
}
