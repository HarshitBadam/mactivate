import MactuationCore
import XCTest
@testable import MactivateRuntime

final class RuntimeFailClosedTests: XCTestCase {
    func testRejectedAndUnmappedGroupsFailClosed() throws {
        let tapSource = ScriptedSensorSource(paths: dualIMUPaths)
        let factory = ScriptedSourceFactory(tapSources: [tapSource])
        let configuration = RuntimeConfiguration(panelHintsEnabled: false)
        let harness = try makeHarness(factory: factory, configuration: configuration)
        harness.controller.start()

        sendIMU(
            to: tapSource,
            duration: 7,
            pulses: [
                // Accepted double, intentionally unmapped.
                (1.0, 0, 0, 0.08),
                (1.4, 0, 0, 0.08),
                // Strong lateral impulse, rejected by the bump veto.
                (4.0, 1.0, 1.0, 0.08)
            ]
        )
        harness.drain()

        XCTAssertTrue(actionIntents(in: harness.collector.outputs).isEmpty)
        let feedback: [TapFeedback] = harness.collector.outputs.compactMap {
            guard case .tapFeedback(let value) = $0 else { return nil }
            return value
        }
        XCTAssertTrue(feedback.contains {
            $0.outcome == .acceptedUnmapped(.leftDouble)
        })
        XCTAssertTrue(feedback.contains {
            if case .rejected = $0.outcome {
                return true
            }
            return false
        })
        harness.controller.stop()
    }

    func testMissingRegionProfileFailsClosedButExposesCalibrationFeatures()
        throws {
        let source = ScriptedSensorSource(paths: dualIMUPaths)
        let harness = try makeHarness(
            factory: ScriptedSourceFactory(tapSources: [source]),
            configuration: RuntimeConfiguration(
                spatialTapBindings: SpatialTapBindings(
                    leftDouble: "left.double"
                ),
                panelHintsEnabled: false
            ),
            provideRegionProfile: false
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
                reason: .calibrationRequired
            ) && $0.regionMemberFeatures.count == 2
        })
        harness.controller.stop()
    }

    func testMissingGyroscopeKeepsTapDiagnosticsButNeverDispatches() throws {
        let source = ScriptedSensorSource(paths: [.spuAccelerometer])
        let harness = try makeHarness(
            factory: ScriptedSourceFactory(tapSources: [source]),
            configuration: RuntimeConfiguration(
                spatialTapBindings: SpatialTapBindings(
                    leftDouble: "left.double"
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
        harness.drain()

        guard case .unavailable =
                harness.controller.currentSnapshot.tapRegion else {
            return XCTFail("missing gyro must be explicit")
        }
        guard case .available = harness.controller.currentSnapshot.tap else {
            return XCTFail("accelerometer tap diagnostics should remain available")
        }
        XCTAssertTrue(actionIntents(in: harness.collector.outputs).isEmpty)
        XCTAssertTrue(tapFeedback(in: harness.collector.outputs).contains {
            $0.outcome == .spatialUnavailable(
                pattern: .double,
                reason: .insufficientGyroscopeData
            )
        })
        harness.controller.stop()
    }

    func testAmbiguousRegionFeatureNeverDispatches() throws {
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
            pulses: [(1, 0, 0, 0.08), (1.4, 0, 0, 0.08)],
            gyroSide: nil
        )
        harness.drain()

        XCTAssertTrue(actionIntents(in: harness.collector.outputs).isEmpty)
        XCTAssertTrue(tapFeedback(in: harness.collector.outputs).contains {
            $0.outcome == .spatialUnavailable(
                pattern: .double,
                reason: .ambiguous
            )
        })
        harness.controller.stop()
    }
}
