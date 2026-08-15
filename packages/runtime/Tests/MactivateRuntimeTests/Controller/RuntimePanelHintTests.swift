import MactuationCore
import XCTest
@testable import MactivateRuntime

final class RuntimePanelHintTests: XCTestCase {
    func testPanelHintTransitionsAndCanOnlyShowPanel() throws {
        let panelSource = ScriptedSensorSource(paths: [.spuAmbientLight])
        let factory = ScriptedSourceFactory(
            tapConstructionError: TestFailure("IMU unavailable"),
            panelSources: [panelSource]
        )
        let harness = try makeHarness(
            factory: factory,
            configuration: RuntimeConfiguration(panelHintsEnabled: true),
            panelCalibration: fastPanelCalibration
        )
        harness.controller.start()

        sendLux([100, 100, 100, 70], to: panelSource)
        harness.drain()

        XCTAssertEqual(harness.controller.currentSnapshot.panelHint, .available)
        let panelIntents = intents(in: harness.collector.outputs)
        XCTAssertEqual(panelIntents.count, 1)
        guard case .showPanel(let reason, let hint) = panelIntents[0] else {
            return XCTFail("ALS emitted an action intent")
        }
        XCTAssertEqual(reason, .ambientLightHint)
        XCTAssertEqual(hint.observedLux, 70)
        XCTAssertTrue(actionIntents(in: harness.collector.outputs).isEmpty)
        harness.controller.stop()
    }

    func testDimPanelHintStateIsExplicit() throws {
        let panelSource = ScriptedSensorSource(paths: [.spuAmbientLight])
        let factory = ScriptedSourceFactory(
            tapConstructionError: TestFailure("IMU unavailable"),
            panelSources: [panelSource]
        )
        let harness = try makeHarness(
            factory: factory,
            configuration: RuntimeConfiguration(panelHintsEnabled: true),
            panelCalibration: fastPanelCalibration
        )
        harness.controller.start()

        sendLux([1, 1, 1], to: panelSource)
        harness.drain()

        XCTAssertEqual(harness.controller.currentSnapshot.panelHint, .tooDim)
        XCTAssertTrue(intents(in: harness.collector.outputs).isEmpty)
        harness.controller.stop()
    }
}
