import XCTest
@testable import MactivateRuntime

final class RuntimeConfigurationControllerTests: XCTestCase {
    func testMappingUpdateDoesNotResetTapAndPanelToggleIsIndependent() throws {
        let tapSource = ScriptedSensorSource(paths: [.spuAccelerometer])
        let panelSource = ScriptedSensorSource(paths: [.spuAmbientLight])
        let factory = ScriptedSourceFactory(
            tapSources: [tapSource],
            panelSources: [panelSource]
        )
        let store = InMemoryRuntimeConfigurationStore(
            result: .loaded(RuntimeConfiguration(panelHintsEnabled: false))
        )
        let harness = try makeHarness(
            factory: factory,
            configurationStore: store,
            panelCalibration: fastPanelCalibration
        )
        harness.controller.start()

        try harness.controller.setSpatialTapBinding(
            "left.double",
            for: .leftDouble
        )
        XCTAssertEqual(tapSource.startCount, 1)
        XCTAssertEqual(tapSource.stopCount, 0)

        try harness.controller.setSpatialTapDispatchEnabled(false)
        XCTAssertFalse(
            store.load().configuration.spatialTapDispatchEnabled
        )
        XCTAssertEqual(tapSource.startCount, 1)
        XCTAssertEqual(tapSource.stopCount, 0)

        try harness.controller.setPanelHintsEnabled(true)
        XCTAssertEqual(panelSource.startCount, 1)
        XCTAssertEqual(tapSource.stopCount, 0)

        try harness.controller.setPanelHintsEnabled(false)
        XCTAssertEqual(panelSource.stopCount, 1)
        XCTAssertEqual(tapSource.stopCount, 0)
        XCTAssertEqual(harness.controller.currentSnapshot.panelHint, .disabled)
        XCTAssertEqual(
            store.load().configuration.spatialTapBindings.leftDouble,
            ActionIdentifier(rawValue: "left.double")
        )
        harness.controller.stop()
    }

    func testBindingChangePreservesAnInFlightTapGroup() throws {
        let tapSource = ScriptedSensorSource(paths: dualIMUPaths)
        let factory = ScriptedSourceFactory(tapSources: [tapSource])
        let harness = try makeHarness(
            factory: factory,
            configuration: RuntimeConfiguration(panelHintsEnabled: false)
        )
        harness.controller.start()

        sendIMU(
            to: tapSource,
            startTime: 0,
            duration: 1.5,
            pulses: [(1.0, 0, 0, 0.08)]
        )
        try harness.controller.setSpatialTapBinding(
            "new.left.double",
            for: .leftDouble
        )
        sendIMU(
            to: tapSource,
            startTime: 1.5,
            duration: 2,
            pulses: [(1.8, 0, 0, 0.08)]
        )
        harness.drain()

        let actions = actionIntents(in: harness.collector.outputs)
        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions.first?.0, "new.left.double")
        XCTAssertEqual(tapSource.startCount, 1)
        XCTAssertEqual(tapSource.stopCount, 0)
        harness.controller.stop()
    }
}
