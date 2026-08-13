import Foundation
import MactivateRuntime

protocol RuntimeControlling: AnyObject {
    var outputHandler: ((RuntimeOutput) -> Void)? { get set }
    var currentConfiguration: RuntimeConfiguration { get }
    var currentSnapshot: RuntimeSnapshot { get }
    var currentTapCalibrationProfile: RuntimeTapCalibrationProfile? { get }
    var tapCalibrationWarning: String? { get }

    func start()
    func stop()
    func setTapBinding(_ action: ActionIdentifier?, for pattern: TapPattern) throws
    func setPanelHintsEnabled(_ enabled: Bool) throws
    func resetConfiguration() throws
    func applyTapCalibration(_ profile: RuntimeTapCalibrationProfile) throws
    func resetTapCalibration() throws
}

final class RuntimeBridge: RuntimeControlling {
    var outputHandler: ((RuntimeOutput) -> Void)?

    private let lifecycleQueue = DispatchQueue(
        label: "com.mactivate.runtime-bridge.lifecycle",
        qos: .utility
    )
    private let calibrationStore: any TapCalibrationProfileStore
    private var controller: MactivateRuntimeController?
    private var calibrationProfile: RuntimeTapCalibrationProfile?
    private(set) var tapCalibrationWarning: String?

    init(
        calibrationStore: any TapCalibrationProfileStore =
            UserDefaultsTapCalibrationProfileStore()
    ) throws {
        self.calibrationStore = calibrationStore
        let loadResult = calibrationStore.load()
        calibrationProfile = loadResult.profile
        if case .invalid(let warning) = loadResult {
            tapCalibrationWarning = warning
        }
        controller = try MactivateRuntimeController(
            tapCalibration: loadResult.profile?.calibration ??
                .mac14_2Discovery
        ) { [weak self] output in
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

    var currentTapCalibrationProfile: RuntimeTapCalibrationProfile? {
        lifecycleQueue.sync { calibrationProfile }
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

    func applyTapCalibration(_ profile: RuntimeTapCalibrationProfile) throws {
        try lifecycleQueue.sync {
            try calibrationStore.save(profile)
            try controller?.applyTapCalibration(profile.calibration)
            calibrationProfile = profile
            tapCalibrationWarning = nil
        }
    }

    func resetTapCalibration() throws {
        try lifecycleQueue.sync {
            calibrationStore.reset()
            try controller?.applyTapCalibration(.mac14_2Discovery)
            calibrationProfile = nil
            tapCalibrationWarning = nil
        }
    }
}
