import MactuationCore
import XCTest
@testable import MactivateRuntime

final class RuntimeSessionIsolationTests: XCTestCase {
    func testOneSourceFailurePreservesTheOtherPath() throws {
        let tapSource = ScriptedSensorSource(paths: [.spuAccelerometer])
        let panelSource = ScriptedSensorSource(paths: [.spuAmbientLight])
        let factory = ScriptedSourceFactory(
            tapSources: [tapSource],
            panelSources: [panelSource]
        )
        let harness = try makeHarness(
            factory: factory,
            configuration: RuntimeConfiguration(panelHintsEnabled: true),
            panelCalibration: fastPanelCalibration
        )
        harness.controller.start()
        sendLux([100, 100, 100], to: panelSource)
        tapSource.send(.failed(
            path: .spuAccelerometer,
            reason: "input reports stopped"
        ))
        harness.drain()

        guard case .unavailable(let reason) =
                harness.controller.currentSnapshot.tap else {
            return XCTFail("tap path should be unavailable")
        }
        XCTAssertEqual(reason, "input reports stopped")
        XCTAssertEqual(harness.controller.currentSnapshot.panelHint, .available)
        XCTAssertEqual(panelSource.stopCount, 0)

        panelSource.send(.sample(.als(
            path: .spuAmbientLight,
            sample: ALSSample(timestamp: 0.3, lux: 70)
        )))
        harness.drain()
        XCTAssertEqual(intents(in: harness.collector.outputs).count, 1)
        harness.controller.stop()
    }

    func testConstructionFailuresAreIndependent() throws {
        let panelSource = ScriptedSensorSource(paths: [.spuAmbientLight])
        let factory = ScriptedSourceFactory(
            tapConstructionError: TestFailure("accelerometer missing"),
            panelSources: [panelSource]
        )
        let harness = try makeHarness(
            factory: factory,
            configuration: RuntimeConfiguration(panelHintsEnabled: true),
            panelCalibration: fastPanelCalibration
        )

        harness.controller.start()

        guard case .unavailable(let reason) =
                harness.controller.currentSnapshot.tap else {
            return XCTFail("tap construction failure was not published")
        }
        XCTAssertTrue(reason.contains("accelerometer missing"))
        XCTAssertEqual(panelSource.startCount, 1)
        XCTAssertEqual(harness.controller.currentSnapshot.panelHint, .warmingUp)
        harness.controller.stop()
    }
}
