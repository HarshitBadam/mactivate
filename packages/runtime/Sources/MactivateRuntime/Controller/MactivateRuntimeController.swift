import Dispatch
import Foundation
import MactuationCore

public final class MactivateRuntimeController {
    public typealias OutputHandler = (RuntimeOutput) -> Void

    let sourceFactory: any RuntimeSourceCreating
    private let configurationStore: any RuntimeConfigurationStore
    let lifecycleMonitor: any RuntimeLifecycleMonitoring
    let runtimeQueue: DispatchQueue
    let deliveryQueue: DispatchQueue
    let outputHandler: OutputHandler
    let queueKey = DispatchSpecificKey<UInt8>()

    var tapClassifier: TapStreamClassifier
    let tapRegionClassifier: TapRegionStreamClassifier
    var tapRegionCalibrationProfile: TapRegionCalibrationProfile?
    let panelDetector: AmbientLightDipDetector
    let tapRouter = RuntimeTapRouter()
    var tapEventLog: RuntimeTapEventLog

    var configuration: RuntimeConfiguration
    var pendingConfigurationWarning: String?
    var snapshot: RuntimeSnapshot
    var lastPublishedSnapshot: RuntimeSnapshot?

    var tapSource: (any SensorSource)?
    var panelSource: (any SensorSource)?
    var tapGeneration: UInt64 = 0
    var panelGeneration: UInt64 = 0
    var sensorSessionID = UUID()

    var monitoringLifecycle = false
    var wasActiveBeforeSleep = false

    public init(
        sourceFactory: any RuntimeSourceCreating = LiveRuntimeFactory(),
        configurationStore: any RuntimeConfigurationStore =
            UserDefaultsRuntimeConfigurationStore(),
        lifecycleMonitor: any RuntimeLifecycleMonitoring =
            WorkspaceRuntimeLifecycleMonitor(),
        tapCalibration: TapCalibration = .mac14_2Discovery,
        tapRegionCalibrationProfile: TapRegionCalibrationProfile? = nil,
        tapStreamConfiguration: TapStreamConfiguration = TapStreamConfiguration(),
        panelCalibration: AmbientLightDipCalibration = .mac14_2Experimental,
        runtimeQueue: DispatchQueue =
            DispatchQueue(label: "com.mactivate.runtime.sensor", qos: .utility),
        deliveryQueue: DispatchQueue = .main,
        emittedTapLimit: Int = 256,
        outputHandler: @escaping OutputHandler
    ) throws {
        precondition(emittedTapLimit > 0, "emittedTapLimit must be positive")
        self.sourceFactory = sourceFactory
        self.configurationStore = configurationStore
        self.lifecycleMonitor = lifecycleMonitor
        self.runtimeQueue = runtimeQueue
        self.deliveryQueue = deliveryQueue
        self.tapEventLog = RuntimeTapEventLog(limit: emittedTapLimit)
        self.outputHandler = outputHandler
        tapClassifier = try TapStreamClassifier(
            calibration: tapCalibration,
            configuration: tapStreamConfiguration
        )
        tapRegionClassifier = try TapRegionStreamClassifier()
        self.tapRegionCalibrationProfile = tapRegionCalibrationProfile?.isValid ==
            true ? tapRegionCalibrationProfile : nil
        panelDetector = try AmbientLightDipDetector(
            calibration: panelCalibration
        )

        let loadResult = configurationStore.load()
        configuration = loadResult.configuration
        pendingConfigurationWarning = loadResult.warning
        snapshot = RuntimeSnapshot(
            lifecycle: .stopped,
            tap: .inactive,
            tapRegion: .inactive,
            panelHint: configuration.panelHintsEnabled ? .inactive : .disabled
        )
        runtimeQueue.setSpecific(key: queueKey, value: 1)
    }

    deinit {
        lifecycleMonitor.stop()
        withRuntimeQueue {
            stopLocked(stopLifecycleMonitor: false)
        }
    }

    public var currentConfiguration: RuntimeConfiguration {
        withRuntimeQueue { configuration }
    }

    public var currentSnapshot: RuntimeSnapshot {
        withRuntimeQueue { snapshot }
    }

    public func start() {
        withRuntimeQueue {
            startLocked()
        }
    }

    public func stop() {
        withRuntimeQueue {
            stopLocked(stopLifecycleMonitor: true)
        }
    }

    public func suspend() {
        withRuntimeQueue {
            wasActiveBeforeSleep = false
            suspendLocked()
        }
    }

    public func resume() {
        withRuntimeQueue {
            resumeLocked()
        }
    }

    public func setConfiguration(_ newConfiguration: RuntimeConfiguration) throws {
        try withRuntimeQueue {
            try applyConfigurationLocked(newConfiguration)
        }
    }

    public func setSpatialTapBinding(
        _ action: ActionIdentifier?,
        for gesture: PalmTapGesture
    ) throws {
        try withRuntimeQueue {
            var updated = configuration
            updated.spatialTapBindings[gesture] = action
            try applyConfigurationLocked(updated)
        }
    }

    public func setSpatialTapDispatchEnabled(_ enabled: Bool) throws {
        try withRuntimeQueue {
            var updated = configuration
            updated.spatialTapDispatchEnabled = enabled
            try applyConfigurationLocked(updated)
        }
    }

    public func setPanelHintsEnabled(_ enabled: Bool) throws {
        try withRuntimeQueue {
            var updated = configuration
            updated.panelHintsEnabled = enabled
            try applyConfigurationLocked(updated)
        }
    }

    public func resetConfiguration() throws {
        try setConfiguration(.default)
    }

    public func applyTapCalibration(_ calibration: TapCalibration) throws {
        try withRuntimeQueue {
            tapClassifier = try TapStreamClassifier(
                calibration: calibration,
                configuration: tapClassifier.configuration
            )
            tapRegionClassifier.reset()
            tapEventLog.reset()
            if tapSource != nil {
                snapshot.tap = .warmingUp
                snapshot.tapRegion = .warmingUp
                publishSnapshotIfChanged()
            }
        }
    }

    public func applyTapRegionCalibration(
        _ profile: TapRegionCalibrationProfile?
    ) throws {
        try withRuntimeQueue {
            if let profile, !profile.isValid {
                throw RuntimeConfigurationStoreError.invalidConfiguration(
                    "left/right calibration profile is invalid"
                )
            }
            tapRegionCalibrationProfile = profile
            tapRegionClassifier.reset()
            tapEventLog.reset()
            if tapSource != nil {
                snapshot.tapRegion = .warmingUp
                publishSnapshotIfChanged()
            }
        }
    }

    func startLocked() {
        guard snapshot.lifecycle == .stopped else { return }
        startLifecycleMonitoringLocked()
        snapshot.lifecycle = .starting
        publishSnapshotIfChanged()
        beginSensorSessionLocked()
        startTapSourceLocked()
        startPanelSourceLocked()
        snapshot.lifecycle = .running
        publishSnapshotIfChanged()
        if let warning = pendingConfigurationWarning {
            pendingConfigurationWarning = nil
            emit(.warning(.configuration(warning)))
        }
    }

    func stopLocked(stopLifecycleMonitor: Bool) {
        guard snapshot.lifecycle != .stopped else {
            if stopLifecycleMonitor { stopLifecycleMonitoringLocked() }
            return
        }
        snapshot.lifecycle = .stopping
        publishSnapshotIfChanged()
        wasActiveBeforeSleep = false
        stopTapSourceLocked(finalState: .inactive)
        stopPanelSourceLocked(
            finalState: configuration.panelHintsEnabled ? .inactive : .disabled
        )
        snapshot.lifecycle = .stopped
        publishSnapshotIfChanged()
        if stopLifecycleMonitor { stopLifecycleMonitoringLocked() }
    }

    func suspendLocked() {
        guard snapshot.lifecycle == .running else { return }
        stopTapSourceLocked(finalState: .inactive)
        stopPanelSourceLocked(
            finalState: configuration.panelHintsEnabled ? .inactive : .disabled
        )
        snapshot.lifecycle = .suspended
        publishSnapshotIfChanged()
    }

    func resumeLocked() {
        guard snapshot.lifecycle == .suspended else { return }
        snapshot.lifecycle = .starting
        publishSnapshotIfChanged()
        beginSensorSessionLocked()
        startTapSourceLocked()
        startPanelSourceLocked()
        snapshot.lifecycle = .running
        publishSnapshotIfChanged()
    }

    func applyConfigurationLocked(
        _ newConfiguration: RuntimeConfiguration
    ) throws {
        guard newConfiguration.isCurrentAndValid else {
            throw RuntimeConfigurationStoreError.invalidConfiguration(
                "configuration must use the current schema and valid action identifiers"
            )
        }
        do {
            try configurationStore.save(newConfiguration)
        } catch {
            emit(.warning(.configuration(
                "could not persist runtime configuration: \(error)"
            )))
            throw error
        }

        let panelEnabledChanged =
            newConfiguration.panelHintsEnabled != configuration.panelHintsEnabled
        configuration = newConfiguration
        pendingConfigurationWarning = nil
        guard panelEnabledChanged else { return }
        if newConfiguration.panelHintsEnabled {
            if snapshot.lifecycle == .running {
                startPanelSourceLocked()
            } else {
                snapshot.panelHint = .inactive
                publishSnapshotIfChanged()
            }
        } else {
            stopPanelSourceLocked(finalState: .disabled)
        }
    }
}
