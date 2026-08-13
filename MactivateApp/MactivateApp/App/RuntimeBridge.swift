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

    private var controller: MactivateRuntimeController?

    init() throws {
        controller = try MactivateRuntimeController { [weak self] output in
            self?.outputHandler?(output)
        }
    }

    var currentConfiguration: RuntimeConfiguration {
        controller?.currentConfiguration ?? .failClosed
    }

    var currentSnapshot: RuntimeSnapshot {
        controller?.currentSnapshot ?? RuntimeSnapshot()
    }

    func start() {
        controller?.start()
    }

    func stop() {
        controller?.stop()
    }

    func setTapBinding(_ action: ActionIdentifier?,
                       for pattern: TapPattern) throws {
        try controller?.setTapBinding(action, for: pattern)
    }

    func setPanelHintsEnabled(_ enabled: Bool) throws {
        try controller?.setPanelHintsEnabled(enabled)
    }

    func resetConfiguration() throws {
        try controller?.resetConfiguration()
    }
}
