import MactuationCore
import XCTest
@testable import MactivateRuntime

final class RuntimeCalibrationControllerTests: XCTestCase {
    func testDiscoveryTapCalibrationCannotDispatchSpatialActions() throws {
        let source = ScriptedSensorSource(paths: dualIMUPaths)
        let harness = try makeHarness(
            factory: ScriptedSourceFactory(tapSources: [source]),
            configuration: RuntimeConfiguration(
                spatialTapBindings: SpatialTapBindings(
                    leftDouble: "left.double"
                ),
                panelHintsEnabled: false
            ),
            tapCalibration: .mac14_2Discovery
        )
        harness.controller.start()

        sendIMU(
            to: source,
            duration: 4,
            pulses: [(1, 0, 0, 0.08), (1.4, 0, 0, 0.08)]
        )
        harness.drain()

        XCTAssertTrue(actionIntents(in: harness.collector.outputs).isEmpty)
        XCTAssertTrue(tapFeedback(in: harness.collector.outputs).contains {
            $0.outcome == .spatialUnavailable(
                pattern: .double,
                reason: .tapCalibrationRequired
            )
        })
        harness.controller.stop()
    }

    func testRegionProfileHotSwapDoesNotRestartSource() throws {
        let source = ScriptedSensorSource(paths: dualIMUPaths)
        let harness = try makeHarness(
            factory: ScriptedSourceFactory(tapSources: [source]),
            configuration: RuntimeConfiguration(
                spatialTapBindings: SpatialTapBindings(
                    leftDouble: "left.double",
                    rightDouble: "right.double"
                ),
                panelHintsEnabled: false
            )
        )
        harness.controller.start()
        sendIMU(
            to: source,
            duration: 4,
            pulses: [(1, 0, 0, 0.08), (1.4, 0, 0, 0.08)]
        )
        try harness.controller.applyTapRegionCalibration(
            TapRegionCalibrationProfile(
                version: "personal-region-swapped",
                lowerBoundary: -1,
                upperBoundary: 1,
                lowerSide: .right,
                samplesPerGesture: 5
            )
        )
        sendIMU(
            to: source,
            startTime: 4,
            duration: 4,
            pulses: [(5, 0, 0, 0.08), (5.4, 0, 0, 0.08)]
        )
        harness.drain()

        XCTAssertEqual(
            actionIntents(in: harness.collector.outputs).map(\.0),
            ["left.double", "right.double"]
        )
        XCTAssertEqual(source.startCount, 1)
        XCTAssertEqual(source.stopCount, 0)
        harness.controller.stop()
    }

    func testCalibrationCanBeReplacedWithoutRestartingSource() throws {
        let tapSource = ScriptedSensorSource(paths: dualIMUPaths)
        let factory = ScriptedSourceFactory(tapSources: [tapSource])
        let harness = try makeHarness(
            factory: factory,
            configuration: RuntimeConfiguration(panelHintsEnabled: false)
        )
        harness.controller.start()
        var calibration = TapCalibration.mac14_2Discovery
        calibration.version = "personal-runtime-test"
        calibration.eventThresholdG = 0.02

        try harness.controller.applyTapCalibration(calibration)
        sendIMU(
            to: tapSource,
            duration: 4,
            pulses: [(2.0, 0, 0, 0.03)]
        )
        harness.drain()

        XCTAssertEqual(tapSource.startCount, 1)
        XCTAssertTrue(actionIntents(in: harness.collector.outputs).isEmpty)
        XCTAssertTrue(tapFeedback(in: harness.collector.outputs).contains {
            $0.outcome == .acceptedNonActionable(.single)
        })
        harness.controller.stop()
    }
}
