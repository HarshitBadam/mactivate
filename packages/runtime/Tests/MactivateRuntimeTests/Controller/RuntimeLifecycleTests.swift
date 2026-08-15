import Dispatch
import MactuationCore
import XCTest
@testable import MactivateRuntime

final class RuntimeLifecycleTests: XCTestCase {
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
}
