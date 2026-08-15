import Dispatch
import Foundation
import MactuationCore
import XCTest
@testable import MactivateRuntime

struct RuntimeHarness {
    let controller: MactivateRuntimeController
    let deliveryQueue: DispatchQueue
    let collector: OutputCollector

    func drain() {
        _ = controller.currentSnapshot
        deliveryQueue.sync {}
    }
}

final class OutputCollector {
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

var personalTapCalibration: TapCalibration {
    var calibration = TapCalibration.mac14_2Discovery
    calibration.version = "personal-runtime-default"
    return calibration
}

var regionProfile: TapRegionCalibrationProfile {
    TapRegionCalibrationProfile(
        version: "personal-region-runtime-test",
        lowerBoundary: -1,
        upperBoundary: 1,
        lowerSide: .left,
        samplesPerGesture: 5
    )
}

var fastPanelCalibration: AmbientLightDipCalibration {
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

func makeHarness(
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

func intents(in outputs: [RuntimeOutput]) -> [RuntimeIntent] {
    outputs.compactMap {
        guard case .intent(let intent) = $0 else { return nil }
        return intent
    }
}

func actionIntents(
    in outputs: [RuntimeOutput]
) -> [(ActionIdentifier, TapTrigger)] {
    intents(in: outputs).compactMap {
        guard case .performAction(let id, let trigger) = $0 else {
            return nil
        }
        return (id, trigger)
    }
}

func tapFeedback(in outputs: [RuntimeOutput]) -> [TapFeedback] {
    outputs.compactMap {
        guard case .tapFeedback(let feedback) = $0 else { return nil }
        return feedback
    }
}

extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
