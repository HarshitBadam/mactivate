import Foundation
import MactuationCore
import XCTest
@testable import MactivateRuntime

final class TapCalibrationProfileStoreTests: XCTestCase {
    func testProfileRoundTripsSeparatelyFromBindings() throws {
        let suite = "TapCalibrationProfileStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = UserDefaultsTapCalibrationProfileStore(
            defaults: defaults,
            key: "calibration"
        )
        let profile = validProfile()

        try store.save(profile)

        XCTAssertEqual(store.load(), .loaded(profile))
        XCTAssertNil(defaults.data(forKey: "com.mactivate.runtime.configuration"))
    }

    func testCorruptProfileNeedsCalibrationWithoutBeingOverwritten() {
        let suite = "TapCalibrationProfileStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let corrupt = Data("{bad".utf8)
        defaults.set(corrupt, forKey: "calibration")
        let store = UserDefaultsTapCalibrationProfileStore(
            defaults: defaults,
            key: "calibration"
        )

        guard case .invalid = store.load() else {
            return XCTFail("corrupt calibration should be invalid")
        }
        XCTAssertEqual(defaults.data(forKey: "calibration"), corrupt)
    }

    func testDiscoveryCalibrationCannotMasqueradeAsPersonalProfile() {
        let profile = TapCalibrationProfile(
            calibration: .mac14_2Discovery,
            sideSummaries: [
                .left: summary,
                .right: summary
            ]
        )

        XCTAssertFalse(profile.isValid)
    }

    private func validProfile() -> TapCalibrationProfile {
        var calibration = TapCalibration.mac14_2Discovery
        calibration.version = "personal-store-test"
        return TapCalibrationProfile(
            calibration: calibration,
            sideSummaries: [
                .left: summary,
                .right: summary
            ]
        )
    }

    private var summary: TapCalibrationSideSummary {
        TapCalibrationSideSummary(
            comfortSampleCount: 5,
            firmSampleCount: 5,
            comfortPeakMedianG: 0.08,
            firmPeakMedianG: 0.3,
            zImpulseMedianMgS: 0.2
        )
    }
}
