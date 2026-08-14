import Dispatch
import Foundation
import MactuationCore

public final class MactivateRuntimeController {
    public typealias OutputHandler = (RuntimeOutput) -> Void

    private let sourceFactory: any RuntimeSourceCreating
    private let configurationStore: any RuntimeConfigurationStore
    private let lifecycleMonitor: any RuntimeLifecycleMonitoring
    private let runtimeQueue: DispatchQueue
    private let deliveryQueue: DispatchQueue
    private let outputHandler: OutputHandler
    private let queueKey = DispatchSpecificKey<UInt8>()

    private var tapClassifier: TapStreamClassifier
    private let tapRegionClassifier: TapRegionStreamClassifier
    private var tapRegionCalibrationProfile: TapRegionCalibrationProfile?
    private let panelDetector: AmbientLightDipDetector

    private var configuration: RuntimeConfiguration
    private var pendingConfigurationWarning: String?
    private var snapshot: RuntimeSnapshot
    private var lastPublishedSnapshot: RuntimeSnapshot?

    private var tapSource: (any SensorSource)?
    private var panelSource: (any SensorSource)?
    private var tapGeneration: UInt64 = 0
    private var panelGeneration: UInt64 = 0
    private var sensorSessionID = UUID()

    private var emittedTapIDs: Set<RuntimeEventID> = []
    private var emittedTapFIFO: [RuntimeEventID] = []
    private let emittedTapLimit: Int

    private var monitoringLifecycle = false
    private var wasActiveBeforeSleep = false

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
        self.emittedTapLimit = emittedTapLimit
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
            emittedTapIDs.removeAll(keepingCapacity: true)
            emittedTapFIFO.removeAll(keepingCapacity: true)
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
            emittedTapIDs.removeAll(keepingCapacity: true)
            emittedTapFIFO.removeAll(keepingCapacity: true)
            if tapSource != nil {
                snapshot.tapRegion = .warmingUp
                publishSnapshotIfChanged()
            }
        }
    }

    private func startLocked() {
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

    private func stopLocked(stopLifecycleMonitor: Bool) {
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

    private func suspendLocked() {
        guard snapshot.lifecycle == .running else { return }
        stopTapSourceLocked(finalState: .inactive)
        stopPanelSourceLocked(
            finalState: configuration.panelHintsEnabled ? .inactive : .disabled
        )
        snapshot.lifecycle = .suspended
        publishSnapshotIfChanged()
    }

    private func resumeLocked() {
        guard snapshot.lifecycle == .suspended else { return }
        snapshot.lifecycle = .starting
        publishSnapshotIfChanged()
        beginSensorSessionLocked()
        startTapSourceLocked()
        startPanelSourceLocked()
        snapshot.lifecycle = .running
        publishSnapshotIfChanged()
    }

    private func beginSensorSessionLocked() {
        sensorSessionID = UUID()
        emittedTapIDs.removeAll(keepingCapacity: true)
        emittedTapFIFO.removeAll(keepingCapacity: true)
        tapClassifier.reset()
        tapRegionClassifier.reset()
        panelDetector.reset()
    }

    private func startTapSourceLocked() {
        tapGeneration &+= 1
        let generation = tapGeneration
        tapClassifier.reset()
        tapRegionClassifier.reset()
        snapshot.tap = .warmingUp
        snapshot.tapRegion = .warmingUp
        publishSnapshotIfChanged()

        do {
            let source = try sourceFactory.makeTapSource()
            tapSource = source
            if !source.paths.contains(.spuGyroscope) {
                snapshot.tapRegion = .unavailable(
                    reason: "Gyroscope is unavailable on this Mac."
                )
                publishSnapshotIfChanged()
            }
            try source.start { [weak self] event in
                self?.runtimeQueue.async { [weak self] in
                    self?.handleTapSourceEvent(event, generation: generation)
                }
            }
        } catch {
            let failedSource = tapSource
            tapSource = nil
            tapGeneration &+= 1
            failedSource?.stop()
            tapClassifier.reset()
            tapRegionClassifier.reset()
            snapshot.tap = .unavailable(reason: String(describing: error))
            snapshot.tapRegion = .unavailable(reason: String(describing: error))
            publishSnapshotIfChanged()
        }
    }

    private func startPanelSourceLocked() {
        guard configuration.panelHintsEnabled else {
            stopPanelSourceLocked(finalState: .disabled)
            return
        }
        panelGeneration &+= 1
        let generation = panelGeneration
        panelDetector.reset()
        snapshot.panelHint = .warmingUp
        publishSnapshotIfChanged()

        do {
            let source = try sourceFactory.makePanelHintSource()
            panelSource = source
            try source.start { [weak self] event in
                self?.runtimeQueue.async { [weak self] in
                    self?.handlePanelSourceEvent(event, generation: generation)
                }
            }
        } catch {
            let failedSource = panelSource
            panelSource = nil
            panelGeneration &+= 1
            failedSource?.stop()
            panelDetector.reset()
            snapshot.panelHint = .unavailable(reason: String(describing: error))
            publishSnapshotIfChanged()
        }
    }

    private func stopTapSourceLocked(finalState: TapFeatureState) {
        tapGeneration &+= 1
        let source = tapSource
        tapSource = nil
        source?.stop()
        tapClassifier.reset()
        tapRegionClassifier.reset()
        snapshot.tap = finalState
        snapshot.tapRegion = .inactive
        publishSnapshotIfChanged()
    }

    private func stopPanelSourceLocked(finalState: PanelHintFeatureState) {
        panelGeneration &+= 1
        let source = panelSource
        panelSource = nil
        source?.stop()
        panelDetector.reset()
        snapshot.panelHint = finalState
        publishSnapshotIfChanged()
    }

    private func handleTapSourceEvent(_ event: SensorSourceEvent,
                                      generation: UInt64) {
        guard generation == tapGeneration, tapSource != nil else { return }
        switch event {
        case .sample(let sample):
            guard case .imu(let path, let imu) = sample else { return }
            do {
                if path == .spuGyroscope {
                    try tapRegionClassifier.append(sample)
                    let regionState: TapRegionFeatureState
                    if let profile = tapRegionCalibrationProfile {
                        regionState = .available(profileVersion: profile.version)
                    } else {
                        regionState = .needsCalibration
                    }
                    if snapshot.tapRegion != regionState {
                        snapshot.tapRegion = regionState
                        publishSnapshotIfChanged()
                    }
                    return
                }
                guard path == .spuAccelerometer else { return }
                let update = try tapClassifier.appendWithFeedback(imu)
                if let measuredRate = tapClassifier.sampleRateHz,
                   snapshot.tap != .available(measuredRateHz: measuredRate) {
                    snapshot.tap = .available(measuredRateHz: measuredRate)
                    publishSnapshotIfChanged()
                }
                for candidate in update.candidates {
                    emit(.tapFeedback(TapFeedback(
                        outcome: .candidate,
                        memberCount: 1,
                        features: candidate,
                        sensorTimestamp: candidate.time,
                        resolutionLatencyS: max(
                            0,
                            sample.timestamp - candidate.time
                        )
                    )))
                }
                for group in update.resolvedGroups {
                    routeTapGroupLocked(
                        group,
                        resolvedAt: sample.timestamp
                    )
                }
            } catch {
                failTapSourceLocked(reason: String(describing: error))
            }
        case .failed(let path, let reason):
            if path == .spuGyroscope {
                tapRegionClassifier.reset()
                snapshot.tapRegion = .unavailable(reason: reason)
                publishSnapshotIfChanged()
                emit(.warning(.source(path: path, message: reason)))
            } else {
                failTapSourceLocked(reason: reason)
            }
        case .warning(let path, let message):
            emit(.warning(.source(path: path, message: message)))
        case .completed:
            failTapSourceLocked(reason: "IMU source completed unexpectedly")
        }
    }

    private func handlePanelSourceEvent(_ event: SensorSourceEvent,
                                        generation: UInt64) {
        guard generation == panelGeneration, panelSource != nil else { return }
        switch event {
        case .sample(let sample):
            guard case .als(let path, _) = sample,
                  path == .spuAmbientLight else { return }
            do {
                for detectorEvent in try panelDetector.process(sample) {
                    switch detectorEvent {
                    case .readinessChanged(let readiness):
                        switch readiness {
                        case .warmingUp: snapshot.panelHint = .warmingUp
                        case .available: snapshot.panelHint = .available
                        case .tooDim: snapshot.panelHint = .tooDim
                        }
                        publishSnapshotIfChanged()
                    case .panelOpenHint(let hint):
                        emit(.intent(.showPanel(
                            reason: .ambientLightHint,
                            hint: hint
                        )))
                    }
                }
            } catch {
                failPanelSourceLocked(reason: String(describing: error))
            }
        case .failed(_, let reason):
            failPanelSourceLocked(reason: reason)
        case .warning(let path, let message):
            emit(.warning(.source(path: path, message: message)))
        case .completed:
            failPanelSourceLocked(reason: "ambient-light source completed unexpectedly")
        }
    }

    private func routeTapGroupLocked(
        _ group: TapGroup,
        resolvedAt: SensorTimestamp
    ) {
        guard let firstMember = group.members.first else { return }
        let latency = max(0, resolvedAt - firstMember.time)
        if !group.verdict.isAccepted {
            emit(.tapFeedback(TapFeedback(
                outcome: .rejected(
                    group.rejectionReason ?? .comfortZImpulse
                ),
                acceptanceVerdict: group.verdict,
                memberCount: group.members.count,
                features: firstMember,
                sensorTimestamp: firstMember.time,
                resolutionLatencyS: latency
            )))
            return
        }
        guard let pattern = TapPattern(rawValue: group.members.count) else {
            emit(.tapFeedback(TapFeedback(
                outcome: .rejected(.tooManyMembers),
                memberCount: group.members.count,
                features: firstMember,
                sensorTimestamp: firstMember.time,
                resolutionLatencyS: latency
            )))
            return
        }
        guard pattern != .single else {
            emit(.tapFeedback(TapFeedback(
                outcome: .acceptedNonActionable(.single),
                acceptanceVerdict: group.verdict,
                memberCount: group.members.count,
                features: firstMember,
                sensorTimestamp: firstMember.time,
                resolutionLatencyS: latency
            )))
            return
        }
        let regionPattern: TapRegionPattern =
            pattern == .double ? .double : .triple
        let rawFeatures: (
            members: [TapRegionMemberFeature],
            median: Double
        )
        do {
            rawFeatures = try tapRegionClassifier.features(for: group)
        } catch {
            emit(.tapFeedback(TapFeedback(
                outcome: .spatialUnavailable(
                    pattern: regionPattern,
                    reason: .insufficientGyroscopeData
                ),
                memberCount: group.members.count,
                features: firstMember,
                sensorTimestamp: firstMember.time,
                resolutionLatencyS: latency,
                regionMemberFeatures: [],
                regionReason: .insufficientGyroscopeData
            )))
            return
        }
        guard tapClassifier.classifier.calibration.version
            .hasPrefix("personal-") else {
            emit(.tapFeedback(TapFeedback(
                outcome: .spatialUnavailable(
                    pattern: regionPattern,
                    reason: .tapCalibrationRequired
                ),
                memberCount: group.members.count,
                features: firstMember,
                sensorTimestamp: firstMember.time,
                resolutionLatencyS: latency,
                regionPrediction: .unknown,
                regionMemberFeatures: rawFeatures.members.map(
                    \.gyroXPeakBalanceDegS
                ),
                regionFeature: rawFeatures.median,
                regionReason: .ambiguous
            )))
            return
        }
        guard let regionProfile = tapRegionCalibrationProfile else {
            emit(.tapFeedback(TapFeedback(
                outcome: .spatialUnavailable(
                    pattern: regionPattern,
                    reason: .calibrationRequired
                ),
                memberCount: group.members.count,
                features: firstMember,
                sensorTimestamp: firstMember.time,
                resolutionLatencyS: latency,
                regionPrediction: .unknown,
                regionMemberFeatures: rawFeatures.members.map(
                    \.gyroXPeakBalanceDegS
                ),
                regionFeature: rawFeatures.median,
                regionReason: .ambiguous
            )))
            return
        }
        let classification = tapRegionClassifier.classify(
            group: group,
            profile: regionProfile
        )
        guard let side = classification.prediction.side else {
            emit(.tapFeedback(TapFeedback(
                outcome: .spatialUnavailable(
                    pattern: regionPattern,
                    reason: spatialUnavailableReason(
                        for: classification.reason
                    )
                ),
                memberCount: group.members.count,
                features: firstMember,
                sensorTimestamp: firstMember.time,
                resolutionLatencyS: latency,
                regionPrediction: classification.prediction,
                regionMemberFeatures: classification.memberFeatures.map(
                    \.gyroXPeakBalanceDegS
                ),
                regionFeature: classification.aggregatedFeature,
                regionProfileVersion: classification.profileVersion,
                regionReason: classification.reason
            )))
            return
        }
        let gesture = PalmTapGesture(side: side, pattern: regionPattern)
        guard let action = configuration.spatialTapBindings[gesture] else {
            emit(.tapFeedback(TapFeedback(
                outcome: .acceptedUnmapped(gesture),
                memberCount: group.members.count,
                features: firstMember,
                sensorTimestamp: firstMember.time,
                resolutionLatencyS: latency,
                regionPrediction: classification.prediction,
                regionMemberFeatures: classification.memberFeatures.map(
                    \.gyroXPeakBalanceDegS
                ),
                regionFeature: classification.aggregatedFeature,
                regionProfileVersion: classification.profileVersion,
                regionReason: classification.reason
            )))
            return
        }
        let eventID = RuntimeEventID(
            sessionID: sensorSessionID,
            classifierEventID: group.eventID(
                calibrationVersion:
                    "\(tapClassifier.classifier.calibration.version)|" +
                    "\(regionProfile.version)|\(side.rawValue)-" +
                    regionPattern.rawValue
            )
        )
        guard reserveTapEventIDLocked(eventID) else {
            emit(.tapFeedback(TapFeedback(
                outcome: .duplicate(gesture),
                memberCount: group.members.count,
                features: firstMember,
                sensorTimestamp: firstMember.time,
                resolutionLatencyS: latency,
                regionPrediction: classification.prediction,
                regionMemberFeatures: classification.memberFeatures.map(
                    \.gyroXPeakBalanceDegS
                ),
                regionFeature: classification.aggregatedFeature,
                regionProfileVersion: classification.profileVersion,
                regionReason: classification.reason
            )))
            return
        }
        emit(.tapFeedback(TapFeedback(
            outcome: .dispatched(gesture: gesture, action: action),
            memberCount: group.members.count,
            features: firstMember,
            sensorTimestamp: firstMember.time,
            resolutionLatencyS: latency,
            regionPrediction: classification.prediction,
            regionMemberFeatures: classification.memberFeatures.map(
                \.gyroXPeakBalanceDegS
            ),
            regionFeature: classification.aggregatedFeature,
            regionProfileVersion: classification.profileVersion,
            regionReason: classification.reason
        )))
        let trigger = TapTrigger(
            eventID: eventID,
            gesture: gesture,
            sensorTimestamp: firstMember.time,
            regionProfileVersion: regionProfile.version
        )
        emit(.intent(.performAction(id: action, trigger: trigger)))
    }

    private func spatialUnavailableReason(
        for reason: TapRegionResolutionReason
    ) -> SpatialTapUnavailableReason {
        switch reason {
        case .invalidProfile: return .invalidProfile
        case .insufficientGyroscopeData: return .insufficientGyroscopeData
        case .ambiguous: return .ambiguous
        case .unsupportedTapCount: return .insufficientGyroscopeData
        case .resolved: return .ambiguous
        }
    }

    private func reserveTapEventIDLocked(_ eventID: RuntimeEventID) -> Bool {
        guard emittedTapIDs.insert(eventID).inserted else { return false }
        emittedTapFIFO.append(eventID)
        if emittedTapFIFO.count > emittedTapLimit {
            let overflow = emittedTapFIFO.count - emittedTapLimit
            for identifier in emittedTapFIFO.prefix(overflow) {
                emittedTapIDs.remove(identifier)
            }
            emittedTapFIFO.removeFirst(overflow)
        }
        return true
    }

    private func failTapSourceLocked(reason: String) {
        tapGeneration &+= 1
        let source = tapSource
        tapSource = nil
        source?.stop()
        tapClassifier.reset()
        tapRegionClassifier.reset()
        snapshot.tap = .unavailable(reason: reason)
        snapshot.tapRegion = .unavailable(reason: reason)
        publishSnapshotIfChanged()
    }

    private func failPanelSourceLocked(reason: String) {
        panelGeneration &+= 1
        let source = panelSource
        panelSource = nil
        source?.stop()
        panelDetector.reset()
        snapshot.panelHint = .unavailable(reason: reason)
        publishSnapshotIfChanged()
    }

    private func applyConfigurationLocked(
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

    private func publishSnapshotIfChanged() {
        guard snapshot != lastPublishedSnapshot else { return }
        lastPublishedSnapshot = snapshot
        emit(.statusChanged(snapshot))
    }

    private func emit(_ output: RuntimeOutput) {
        deliveryQueue.async { [outputHandler] in
            outputHandler(output)
        }
    }

    private func startLifecycleMonitoringLocked() {
        guard !monitoringLifecycle else { return }
        monitoringLifecycle = true
        lifecycleMonitor.start(
            onSleep: { [weak self] in self?.handleSystemSleep() },
            onWake: { [weak self] in self?.handleSystemWake() }
        )
    }

    private func stopLifecycleMonitoringLocked() {
        guard monitoringLifecycle else { return }
        monitoringLifecycle = false
        lifecycleMonitor.stop()
    }

    private func handleSystemSleep() {
        withRuntimeQueue {
            guard snapshot.lifecycle == .running else {
                wasActiveBeforeSleep = false
                return
            }
            wasActiveBeforeSleep = true
            suspendLocked()
        }
    }

    private func handleSystemWake() {
        withRuntimeQueue {
            guard wasActiveBeforeSleep else { return }
            wasActiveBeforeSleep = false
            resumeLocked()
        }
    }

    private func withRuntimeQueue<T>(_ body: () throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            return try body()
        }
        return try runtimeQueue.sync(execute: body)
    }
}
