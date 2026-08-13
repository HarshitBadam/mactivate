import MactuationCore
@testable import MactuationHardware
import XCTest

final class HardwareContractTests: XCTestCase {
    func testInvalidALSConfigurationFailsBeforeHardwareLookup() {
        XCTAssertThrowsError(try RegistryALSSource(pollHz: 0)) {
            XCTAssertEqual(
                $0 as? HardwareError,
                .invalidConfiguration("pollHz must be greater than zero")
            )
        }
        XCTAssertThrowsError(
            try RegistryALSSource(pollHz: 10, reportIntervalOverride: 0)
        ) {
            XCTAssertEqual(
                $0 as? HardwareError,
                .invalidConfiguration(
                    "report interval must be a positive number of microseconds"
                )
            )
        }
    }

    func testSnapshotReturnsUnknownForUnmeasuredPath() {
        let snapshot = SPUHardwareSnapshot(
            services: [],
            states: [.spuAccelerometer: .available(detail: "measured")],
            currentAmbientLux: nil
        )

        XCTAssertEqual(
            snapshot.state(of: .spuAccelerometer),
            .available(detail: "measured")
        )
        XCTAssertEqual(snapshot.state(of: .camera), .unknown)
    }

    func testHardwareErrorDescriptionIsActionable() {
        XCTAssertEqual(
            HardwareError.deviceAbsent(.spuAccelerometer).description,
            "spu_accelerometer HID service is absent"
        )
    }
}
