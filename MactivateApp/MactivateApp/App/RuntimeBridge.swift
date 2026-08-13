import Foundation
import MactivateRuntime

protocol RuntimeControlling: AnyObject {
    var outputHandler: ((RuntimeOutput) -> Void)? { get set }
    var currentConfiguration: RuntimeConfiguration { get }
    var currentSnapshot: RuntimeSnapshot { get }

    func start()
    func stop()
    func setTapBinding(_ action: ActionIdentifier?, for pattern: TapPattern) throws
    func setPanelHintsEnabled(_ enabled: Bool) throws
    func resetConfiguration() throws
}

final class RuntimeBridge: RuntimeControlling {
    var outputHandler: ((RuntimeOutput) -> Void)?

    private let lifecycleQueue = DispatchQueue(
        label: "com.mactivate.runtime-bridge.lifecycle",
        qos: .utility
    )
    private var controller: MactivateRuntimeController?

    init() throws {
        controller = try MactivateRuntimeController { [weak self] output in
            self?.outputHandler?(output)
        }
    }

    var currentConfiguration: RuntimeConfiguration {
        lifecycleQueue.sync {
            controller?.currentConfiguration ?? .failClosed
        }
    }

    var currentSnapshot: RuntimeSnapshot {
        lifecycleQueue.sync {
            controller?.currentSnapshot ?? RuntimeSnapshot()
        }
    }

    func start() {
        lifecycleQueue.async(qos: .utility, flags: .enforceQoS) { [controller] in
            controller?.start()
        }
    }

    func stop() {
        lifecycleQueue.sync {
            controller?.stop()
        }
    }

    func setTapBinding(_ action: ActionIdentifier?,
                       for pattern: TapPattern) throws {
        try lifecycleQueue.sync {
            try controller?.setTapBinding(action, for: pattern)
        }
    }

    func setPanelHintsEnabled(_ enabled: Bool) throws {
        try lifecycleQueue.sync {
            try controller?.setPanelHintsEnabled(enabled)
        }
    }

    func resetConfiguration() throws {
        try lifecycleQueue.sync {
            try controller?.resetConfiguration()
        }
    }
}
