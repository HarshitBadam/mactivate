import Dispatch
import Foundation
import MactuationCore
import XCTest
@testable import MactivateRuntime

final class MactivateRuntimeControllerTests: XCTestCase {
    private let rate = 800.0
    private let dualIMUPaths: [SensorPath] = [
        .spuAccelerometer,
        .spuGyroscope
    ]

    private var personalTapCalibration: TapCalibration {
        var calibration = TapCalibration.mac14_2Discovery
        calibration.version = "personal-runtime-default"
        return calibration
    }

    private var regionProfile: TapRegionCalibrationProfile {
        TapRegionCalibrationProfile(
            version: "personal-region-runtime-test",
            lowerBoundary: -1,
            upperBoundary: 1,
            lowerSide: .left,
            samplesPerGesture: 5
        )
    }

    func testRoutesAllFourSpatialGesturesAndKeepsSingleNonActionable() throws {
        let tapSource = ScriptedSensorSource(paths: dualIMUPaths)
        let factory = ScriptedSourceFactory(tapSources: [tapSource])
        let configuration = RuntimeConfiguration(
            spatialTapBindings: SpatialTapBindings(
                leftDouble: "left.double",
                leftTriple: "left.triple",
                rightDouble: "right.double",
                rightTriple: "right.triple"
            ),
            panelHintsEnabled: false
        )
        let harness = try makeHarness(factory: factory, configuration: configuration)
        harness.controller.start()

        sendIMU(
            to: tapSource,
            duration: 10,
            pulses: [
                // Single remains diagnostic-only.
                (1.0, 0, 0, 0.08),
                (3.0, 0, 0, 0.08),
                (3.4, 0, 0, 0.08),
                (6.0, 0, 0, 0.08),
                (6.35, 0, 0, 0.08),
                (6.7, 0, 0, 0.08)
            ]
        )
        sendIMU(
            to: tapSource,
            startTime: 10,
            duration: 8,
            pulses: [
                (11.0, 0, 0, 0.08),
                (11.4, 0, 0, 0.08),
                (14.0, 0, 0, 0.08),
                (14.35, 0, 0, 0.08),
                (14.7, 0, 0, 0.08)
            ],
            gyroSide: .right
        )
        harness.drain()

        let actions = actionIntents(in: harness.collector.outputs)
        XCTAssertEqual(actions.map(\.0), [
            ActionIdentifier(rawValue: "left.double"),
            ActionIdentifier(rawValue: "left.triple"),
            ActionIdentifier(rawValue: "right.double"),
            ActionIdentifier(rawValue: "right.triple")
        ])
        XCTAssertEqual(actions.map(\.1.gesture), [
            .leftDouble, .leftTriple, .rightDouble, .rightTriple
        ])
        XCTAssertEqual(Set(actions.map(\.1.eventID)).count, 4)
        XCTAssertTrue(tapFeedback(in: harness.collector.outputs).contains {
            $0.outcome == .acceptedNonActionable(.single) &&
                $0.acceptanceVerdict == .acceptedComfort
        })

        harness.controller.stop()
    }

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
        let intents = intents(in: harness.collector.outputs)
        XCTAssertEqual(intents.count, 1)
        guard case .showPanel(let reason, let hint) = intents[0] else {
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

    func testRepeatedStartStopAndUnresolvedTapAreSafe() throws {
        let firstTapSource = ScriptedSensorSource(paths: [.spuAccelerometer])
        let secondTapSource = ScriptedSensorSource(paths: [.spuAccelerometer])
        let factory = ScriptedSourceFactory(
            tapSources: [firstTapSource, secondTapSource]
        )
        let configuration = RuntimeConfiguration(panelHintsEnabled: false)
        let harness = try makeHarness(factory: factory, configuration: configuration)
        harness.controller.start()
        harness.controller.start()
        XCTAssertEqual(firstTapSource.startCount, 1)

        sendIMU(
            to: firstTapSource,
            duration: 2.4,
            pulses: [(2.0, 0, 0, 0.08)]
        )
        harness.controller.stop()
        harness.controller.stop()
        harness.drain()

        XCTAssertEqual(firstTapSource.stopCount, 1)
        XCTAssertTrue(actionIntents(in: harness.collector.outputs).isEmpty)

        harness.controller.start()
        XCTAssertEqual(secondTapSource.startCount, 1)
        harness.controller.stop()
    }

    func testSleepWakeRecreatesSourcesRejectsLateCallbacksAndIsolatesIDs() throws {
        let firstTapSource = ScriptedSensorSource(paths: dualIMUPaths)
        let secondTapSource = ScriptedSensorSource(paths: dualIMUPaths)
        let factory = ScriptedSourceFactory(
            tapSources: [firstTapSource, secondTapSource]
        )
        let lifecycle = TestLifecycleMonitor()
        let configuration = RuntimeConfiguration(
            spatialTapBindings: SpatialTapBindings(
                leftDouble: "left.double"
            ),
            panelHintsEnabled: false
        )
        let harness = try makeHarness(
            factory: factory,
            configuration: configuration,
            lifecycleMonitor: lifecycle
        )
        harness.controller.start()
        sendIMU(
            to: firstTapSource,
            duration: 3.5,
            pulses: [
                (1.0, 0, 0, 0.08),
                (1.4, 0, 0, 0.08)
            ]
        )
        harness.drain()

        lifecycle.fireSleep()
        XCTAssertEqual(harness.controller.currentSnapshot.lifecycle, .suspended)
        XCTAssertEqual(firstTapSource.stopCount, 1)
        lifecycle.fireWake()
        XCTAssertEqual(harness.controller.currentSnapshot.lifecycle, .running)
        XCTAssertEqual(secondTapSource.startCount, 1)

        firstTapSource.send(.failed(
            path: .spuAccelerometer,
            reason: "late old-session failure"
        ))
        sendIMU(
            to: secondTapSource,
            duration: 3.5,
            pulses: [
                (1.0, 0, 0, 0.08),
                (1.4, 0, 0, 0.08)
            ]
        )
        harness.drain()

        let actions = actionIntents(in: harness.collector.outputs)
        XCTAssertEqual(actions.count, 2)
        XCTAssertNotEqual(
            actions[0].1.eventID.sessionID,
            actions[1].1.eventID.sessionID
        )
        guard case .available = harness.controller.currentSnapshot.tap else {
            return XCTFail("late callback changed the new tap path")
        }

        lifecycle.fireWake()
        XCTAssertEqual(secondTapSource.startCount, 1)
        harness.controller.stop()
    }

    func testOutputsUseInjectedDeliveryQueue() throws {
        let deliveryQueue = DispatchQueue(label: "test.runtime.delivery")
        let deliveryKey = DispatchSpecificKey<Bool>()
        deliveryQueue.setSpecific(key: deliveryKey, value: true)
        let tapSource = ScriptedSensorSource(paths: [.spuAccelerometer])
        let factory = ScriptedSourceFactory(tapSources: [tapSource])
        let collector = OutputCollector()
        let store = InMemoryRuntimeConfigurationStore(
            result: .loaded(RuntimeConfiguration(panelHintsEnabled: false))
        )
        let controller = try MactivateRuntimeController(
            sourceFactory: factory,
            configurationStore: store,
            lifecycleMonitor: TestLifecycleMonitor(),
            deliveryQueue: deliveryQueue
        ) { output in
            collector.append(
                output,
                deliveredOnExpectedQueue:
                    DispatchQueue.getSpecific(key: deliveryKey) == true
            )
        }

        controller.start()
        _ = controller.currentSnapshot
        deliveryQueue.sync {}

        XCTAssertFalse(collector.outputs.isEmpty)
        XCTAssertTrue(collector.allDeliveredOnExpectedQueue)
        controller.stop()
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

    private var fastPanelCalibration: AmbientLightDipCalibration {
        AmbientLightDipCalibration(
            version: "runtime-test-1",
            warmupSampleCount: 3,
            minimumBaselineLux: 30,
            floorLux: 1.5,
            floorConfirmationS: 1,
            minimumAbsoluteDropLux: 5,
            minimumRelativeDrop: 0.20,
            recoveryFraction: 0.90,
            maximumDipS: 3,
            baselineSmoothingFactor: 0.02,
            cooldownS: 2
        )
    }

    private func makeHarness(
        factory: ScriptedSourceFactory,
        configuration: RuntimeConfiguration? = nil,
        configurationStore: InMemoryRuntimeConfigurationStore? = nil,
        lifecycleMonitor: TestLifecycleMonitor = TestLifecycleMonitor(),
        panelCalibration: AmbientLightDipCalibration = .mac14_2Experimental,
        tapCalibration: TapCalibration? = nil,
        provideRegionProfile: Bool = true
    ) throws -> RuntimeHarness {
        let store = configurationStore ?? InMemoryRuntimeConfigurationStore(
            result: .loaded(configuration ?? .default)
        )
        let deliveryQueue = DispatchQueue(
            label: "test.runtime.delivery.\(UUID().uuidString)"
        )
        let collector = OutputCollector()
        let controller = try MactivateRuntimeController(
            sourceFactory: factory,
            configurationStore: store,
            lifecycleMonitor: lifecycleMonitor,
            tapCalibration: tapCalibration ?? personalTapCalibration,
            tapRegionCalibrationProfile:
                provideRegionProfile ? regionProfile : nil,
            panelCalibration: panelCalibration,
            deliveryQueue: deliveryQueue
        ) { output in
            collector.append(output)
        }
        return RuntimeHarness(
            controller: controller,
            deliveryQueue: deliveryQueue,
            collector: collector
        )
    }

    private func sendIMU(
        to source: ScriptedSensorSource,
        startTime: Double = 0,
        duration: Double,
        pulses: [(Double, Double, Double, Double)],
        gyroSide: TapRegionSide? = .left
    ) {
        let firstIndex = Int(startTime * rate)
        let endIndex = Int((startTime + duration) * rate)
        for index in firstIndex..<endIndex {
            let time = Double(index) / rate
            var x = 0.02
            var y = -0.01
            var z = -1.0
            for pulse in pulses {
                let delta = time - pulse.0
                if delta >= 0, delta < 0.025 {
                    let decay = exp(-delta / 0.005)
                    x += pulse.1 * decay
                    y += pulse.2 * decay
                    z += pulse.3 * decay
                }
            }
            var gyroX = 0.0
            for pulse in pulses {
                let delta = time - pulse.0
                if delta >= -0.02, delta < 0 {
                    switch gyroSide {
                    case .left: gyroX = -4
                    case .right: gyroX = -1
                    case nil: gyroX = -1
                    }
                } else if delta >= 0, delta <= 0.02 {
                    switch gyroSide {
                    case .left: gyroX = 1
                    case .right: gyroX = 4
                    case nil: gyroX = 1
                    }
                }
            }
            if source.paths.contains(.spuGyroscope) {
                source.send(.sample(.imu(
                    path: .spuGyroscope,
                    sample: IMUSample(
                        timestamp: time,
                        x: gyroX,
                        y: 0,
                        z: 0
                    )
                )))
            }
            source.send(.sample(.imu(
                path: .spuAccelerometer,
                sample: IMUSample(timestamp: time, x: x, y: y, z: z)
            )))
        }
    }

    private func sendLux(_ values: [Double],
                         to source: ScriptedSensorSource) {
        for (index, lux) in values.enumerated() {
            source.send(.sample(.als(
                path: .spuAmbientLight,
                sample: ALSSample(timestamp: Double(index) * 0.1, lux: lux)
            )))
        }
    }

    private func intents(in outputs: [RuntimeOutput]) -> [RuntimeIntent] {
        outputs.compactMap {
            guard case .intent(let intent) = $0 else { return nil }
            return intent
        }
    }

    private func actionIntents(
        in outputs: [RuntimeOutput]
    ) -> [(ActionIdentifier, TapTrigger)] {
        intents(in: outputs).compactMap {
            guard case .performAction(let id, let trigger) = $0 else {
                return nil
            }
            return (id, trigger)
        }
    }

    private func tapFeedback(in outputs: [RuntimeOutput]) -> [TapFeedback] {
        outputs.compactMap {
            guard case .tapFeedback(let feedback) = $0 else { return nil }
            return feedback
        }
    }
}

private struct RuntimeHarness {
    let controller: MactivateRuntimeController
    let deliveryQueue: DispatchQueue
    let collector: OutputCollector

    func drain() {
        _ = controller.currentSnapshot
        deliveryQueue.sync {}
    }
}

private final class OutputCollector {
    private let lock = NSLock()
    private var storage: [RuntimeOutput] = []
    private var deliveryChecks: [Bool] = []

    var outputs: [RuntimeOutput] {
        lock.withLock { storage }
    }

    var allDeliveredOnExpectedQueue: Bool {
        lock.withLock { deliveryChecks.allSatisfy { $0 } }
    }

    func append(_ output: RuntimeOutput,
                deliveredOnExpectedQueue: Bool = true) {
        lock.withLock {
            storage.append(output)
            deliveryChecks.append(deliveredOnExpectedQueue)
        }
    }
}

private final class ScriptedSensorSource: SensorSource {
    let paths: [SensorPath]
    var startError: Error?
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private var handler: ((SensorSourceEvent) -> Void)?

    init(paths: [SensorPath], startError: Error? = nil) {
        self.paths = paths
        self.startError = startError
    }

    func start(handler: @escaping (SensorSourceEvent) -> Void) throws {
        startCount += 1
        if let startError { throw startError }
        self.handler = handler
    }

    func stop() {
        stopCount += 1
    }

    func send(_ event: SensorSourceEvent) {
        handler?(event)
    }
}

private final class ScriptedSourceFactory: RuntimeSourceCreating {
    private var tapSources: [ScriptedSensorSource]
    private var panelSources: [ScriptedSensorSource]
    private let tapConstructionError: Error?
    private let panelConstructionError: Error?

    init(tapSources: [ScriptedSensorSource] = [],
         tapConstructionError: Error? = nil,
         panelSources: [ScriptedSensorSource] = [],
         panelConstructionError: Error? = nil) {
        self.tapSources = tapSources
        self.tapConstructionError = tapConstructionError
        self.panelSources = panelSources
        self.panelConstructionError = panelConstructionError
    }

    func makeTapSource() throws -> any SensorSource {
        if let tapConstructionError { throw tapConstructionError }
        guard !tapSources.isEmpty else {
            throw TestFailure("no scripted tap source remains")
        }
        return tapSources.removeFirst()
    }

    func makePanelHintSource() throws -> any SensorSource {
        if let panelConstructionError { throw panelConstructionError }
        guard !panelSources.isEmpty else {
            throw TestFailure("no scripted panel source remains")
        }
        return panelSources.removeFirst()
    }
}

private final class TestLifecycleMonitor: RuntimeLifecycleMonitoring {
    private var onSleep: (() -> Void)?
    private var onWake: (() -> Void)?

    func start(onSleep: @escaping () -> Void,
               onWake: @escaping () -> Void) {
        self.onSleep = onSleep
        self.onWake = onWake
    }

    func stop() {
        onSleep = nil
        onWake = nil
    }

    func fireSleep() {
        onSleep?()
    }

    func fireWake() {
        onWake?()
    }
}

private struct TestFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
