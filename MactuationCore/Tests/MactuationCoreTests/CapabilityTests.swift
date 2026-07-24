import XCTest
@testable import MactuationCore

final class CapabilityTests: XCTestCase {
    func testAllPathsStartUnknown() {
        let report = CapabilityReport.allUnknown()
        for path in SensorPath.allCases {
            XCTAssertEqual(report.state(of: path), .unknown)
            XCTAssertFalse(report.state(of: path).allowsAcquisition)
        }
    }

    func testOnlyAvailableAllowsAcquisition() {
        XCTAssertTrue(CapabilityState.available(detail: "probe-confirmed").allowsAcquisition)
        XCTAssertFalse(CapabilityState.needsPrivilege(privilege: "root").allowsAcquisition)
        XCTAssertFalse(CapabilityState.needsOptIn.allowsAcquisition)
        XCTAssertFalse(CapabilityState.unavailable(reason: "no SPU").allowsAcquisition)
    }

    func testReportRoundTripsThroughJSON() throws {
        var report = CapabilityReport.allUnknown()
        report.states[.spuAccelerometer] = .needsPrivilege(privilege: "root")
        report.states[.camera] = .needsOptIn
        report.states[.displayServicesAmbientLight] = .available(detail: "AggregatedLux readable")

        let data = try JSONEncoder().encode(report)
        let restored = try JSONDecoder().decode(CapabilityReport.self, from: data)
        XCTAssertEqual(restored.state(of: .spuAccelerometer), .needsPrivilege(privilege: "root"))
        XCTAssertEqual(restored.state(of: .camera), .needsOptIn)
        XCTAssertEqual(restored.state(of: .displayServicesAmbientLight),
                       .available(detail: "AggregatedLux readable"))
    }
}
