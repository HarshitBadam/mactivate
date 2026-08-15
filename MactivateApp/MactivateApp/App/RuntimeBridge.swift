import Foundation
import MactivateRuntime

protocol RuntimeControlling: AnyObject {
    var outputHandler: ((RuntimeOutput) -> Void)? { get set }
    var currentConfiguration: RuntimeConfiguration { get }
    var currentSnapshot: RuntimeSnapshot { get }
    var currentTapCalibrationProfile: RuntimeTapCalibrationProfile? { get }
    var currentTapRegionCalibrationProfile: RuntimeTapRegionCalibrationProfile? {
        get
    }
    var tapCalibrationWarning: String? { get }
    var tapRegionCalibrationWarning: String? { get }

    func start()
    func stop()
    func setSpatialTapBinding(
        _ action: ActionIdentifier?,
        for gesture: PalmTapGesture
    ) throws
    func setSpatialTapDispatchEnabled(_ enabled: Bool) throws
    func setPanelHintsEnabled(_ enabled: Bool) throws
    func resetConfiguration() throws
    func applyTapCalibration(_ profile: RuntimeTapCalibrationProfile) throws
    func resetTapCalibration() throws
    func applyTapRegionCalibration(
        _ profile: RuntimeTapRegionCalibrationProfile
    ) throws
    func resetTapRegionCalibration() throws
}

final class RuntimeBridge: RuntimeControlling {
    var outputHandler: ((RuntimeOutput) -> Void)?

    private let lifecycleQueue = DispatchQueue(
        label: "com.mactivate.runtime-bridge.lifecycle",
        qos: .utility
    )
    private let calibrationStore: any TapCalibrationProfileStore
    private let regionCalibrationStore: any TapRegionCalibrationProfileStore
    private var controller: MactivateRuntimeController?
    private var calibrationProfile: RuntimeTapCalibrationProfile?
    private var regionCalibrationProfile: RuntimeTapRegionCalibrationProfile?
    private(set) var tapCalibrationWarning: String?
    private(set) var tapRegionCalibrationWarning: String?

    init(
        calibrationStore: any TapCalibrationProfileStore =
            UserDefaultsTapCalibrationProfileStore(),
        regionCalibrationStore: any TapRegionCalibrationProfileStore =
            UserDefaultsTapRegionCalibrationProfileStore(),
        sourceFactory: any RuntimeSourceCreating = LiveRuntimeFactory(
            includeGyroscope:
                ProcessInfo.processInfo.environment[
                    "MACTIVATE_FORCE_NO_GYRO"
                ] != "1"
        )
    ) throws {
        self.calibrationStore = calibrationStore
        self.regionCalibrationStore = regionCalibrationStore
        let loadResult = calibrationStore.load()
        let regionLoadResult = regionCalibrationStore.load()
        calibrationProfile = loadResult.profile
        regionCalibrationProfile = regionLoadResult.profile
        if case .invalid(let warning) = loadResult {
            tapCalibrationWarning = warning
        }
        tapRegionCalibrationWarning = regionLoadResult.warning
        controller = try MactivateRuntimeController(
            sourceFactory: sourceFactory,
            tapCalibration: loadResult.profile?.calibration ??
                .mac14_2Discovery,
            tapRegionCalibrationProfile: regionLoadResult.profile
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

    var currentTapRegionCalibrationProfile:
        RuntimeTapRegionCalibrationProfile? {
        lifecycleQueue.sync { regionCalibrationProfile }
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

    func setSpatialTapBinding(
        _ action: ActionIdentifier?,
        for gesture: PalmTapGesture
    ) throws {
        try lifecycleQueue.sync {
            try controller?.setSpatialTapBinding(action, for: gesture)
        }
    }

    func setSpatialTapDispatchEnabled(_ enabled: Bool) throws {
        try lifecycleQueue.sync {
            try controller?.setSpatialTapDispatchEnabled(enabled)
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

    func applyTapRegionCalibration(
        _ profile: RuntimeTapRegionCalibrationProfile
    ) throws {
        try lifecycleQueue.sync {
            try regionCalibrationStore.save(profile)
            try controller?.applyTapRegionCalibration(profile)
            regionCalibrationProfile = profile
            tapRegionCalibrationWarning = nil
        }
    }

    func resetTapRegionCalibration() throws {
        try lifecycleQueue.sync {
            regionCalibrationStore.reset()
            try controller?.applyTapRegionCalibration(nil)
            regionCalibrationProfile = nil
            tapRegionCalibrationWarning = nil
        }
    }
}
