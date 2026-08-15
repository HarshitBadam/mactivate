import Foundation
import MactuationCore

extension MactivateRuntimeController {
    func beginSensorSessionLocked() {
        sensorSessionID = UUID()
        tapEventLog.reset()
        tapClassifier.reset()
        tapRegionClassifier.reset()
        panelDetector.reset()
    }

    func startTapSourceLocked() {
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

    func startPanelSourceLocked() {
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

    func stopTapSourceLocked(finalState: TapFeatureState) {
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

    func stopPanelSourceLocked(finalState: PanelHintFeatureState) {
        panelGeneration &+= 1
        let source = panelSource
        panelSource = nil
        source?.stop()
        panelDetector.reset()
        snapshot.panelHint = finalState
        publishSnapshotIfChanged()
    }

    func handleTapSourceEvent(_ event: SensorSourceEvent,
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

    func handlePanelSourceEvent(_ event: SensorSourceEvent,
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

    func failTapSourceLocked(reason: String) {
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

    func failPanelSourceLocked(reason: String) {
        panelGeneration &+= 1
        let source = panelSource
        panelSource = nil
        source?.stop()
        panelDetector.reset()
        snapshot.panelHint = .unavailable(reason: reason)
        publishSnapshotIfChanged()
    }

    func routeTapGroupLocked(
        _ group: TapGroup,
        resolvedAt: SensorTimestamp
    ) {
        tapRouter.route(
            group,
            resolvedAt: resolvedAt,
            tapCalibrationVersion: tapClassifier.classifier.calibration.version,
            regionClassifier: tapRegionClassifier,
            regionProfile: tapRegionCalibrationProfile,
            configuration: configuration,
            sessionID: sensorSessionID,
            eventLog: &tapEventLog,
            emit: emit
        )
    }
}
