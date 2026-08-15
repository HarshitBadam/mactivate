import MactivateRuntime

extension AppCoordinator {
    func handleTapFeedback(_ feedback: TapFeedback) {
        state.lastTapFeedback = feedback
        if let target = state.tapRegionCalibrationTarget,
           feedback.outcome != .candidate {
            if isAcceptedForRegionCalibration(feedback.outcome) {
                if case .dispatched = feedback.outcome {
                    suppressNextCalibrationTapIntent = true
                }
                do {
                    try state.tapRegionCalibrationDraft.record(
                        feedback,
                        target: target
                    )
                    state.tapRegionCalibrationError = nil
                    advanceRegionCalibration(after: target)
                } catch {
                    state.tapRegionCalibrationError =
                        String(describing: error)
                }
            } else if case .rejected(let reason) = feedback.outcome {
                state.tapRegionCalibrationError =
                    "Gesture rejected. \(reason.guidance)"
            } else if case .spatialUnavailable(_, let reason) =
                        feedback.outcome {
                state.tapRegionCalibrationError = reason.message
            }
        } else if let target = state.tapCalibrationTarget,
                  feedback.outcome != .candidate {
            do {
                try state.tapCalibrationDraft.record(
                    feedback,
                    side: target.side,
                    intensity: target.intensity
                )
                state.tapCalibrationError = nil
                if state.tapCalibrationDraft.sampleCount(
                    side: target.side,
                    intensity: target.intensity
                ) >= TapCalibrationDraft.requiredSamplesPerTarget {
                    state.tapCalibrationTarget = nil
                }
            } catch {
                state.tapCalibrationError = String(describing: error)
            }
        }
    }

    func beginCalibrationCapture(_ target: TapCalibrationTarget) {
        state.tapRegionCalibrationTarget = nil
        state.tapCalibrationTarget = nil
        state.tapCalibrationDraft.reset(
            side: target.side,
            intensity: target.intensity
        )
        state.tapCalibrationError = nil
        state.lastTapFeedback = nil
        state.tapCalibrationTarget = target
    }

    func saveCalibration() {
        state.tapCalibrationTarget = nil
        state.tapRegionCalibrationTarget = nil
        do {
            let profile = try state.tapCalibrationDraft.buildProfile()
            try runtime.applyTapCalibration(profile)
            state.tapCalibrationProfile = profile
            state.tapCalibrationError = nil
            clearTapCalibrationStoreWarning()
        } catch {
            state.tapCalibrationError = String(describing: error)
        }
    }

    func resetCalibration() {
        do {
            state.tapRegionCalibrationTarget = nil
            try runtime.resetTapCalibration()
            state.tapCalibrationDraft.reset()
            state.tapCalibrationTarget = nil
            state.tapCalibrationProfile = nil
            state.tapCalibrationError = nil
            clearTapCalibrationStoreWarning()
        } catch {
            state.tapCalibrationError = error.localizedDescription
        }
    }

    func beginRegionCalibration() {
        guard state.canCalibrateTapRegion else {
            state.tapRegionCalibrationError =
                "Complete tap-acceptance calibration and connect the gyroscope first."
            return
        }
        state.tapCalibrationTarget = nil
        state.tapRegionCalibrationDraft.reset()
        state.tapRegionCalibrationError = nil
        state.lastTapFeedback = nil
        state.tapRegionCalibrationTarget =
            TapRegionCalibrationTarget.ordered.first
    }

    private func advanceRegionCalibration(
        after target: TapRegionCalibrationTarget
    ) {
        let required =
            TapRegionCalibrationDraft.requiredGesturesPerTarget
        guard state.tapRegionCalibrationDraft.sampleCount(target: target) >=
                required else {
            return
        }
        if let next = TapRegionCalibrationTarget.ordered.first(where: {
            state.tapRegionCalibrationDraft.sampleCount(target: $0) < required
        }) {
            state.tapRegionCalibrationTarget = next
        } else {
            state.tapRegionCalibrationTarget = nil
            saveRegionCalibration()
        }
    }

    func saveRegionCalibration() {
        state.tapRegionCalibrationTarget = nil
        do {
            let result = try state.tapRegionCalibrationDraft.buildProfile()
            try runtime.applyTapRegionCalibration(result.profile)
            state.tapRegionCalibrationProfile = result.profile
            state.tapRegionCalibrationError = nil
            clearTapRegionCalibrationStoreWarning()
        } catch {
            state.tapRegionCalibrationError = String(describing: error)
        }
    }

    func resetRegionCalibration() {
        do {
            state.tapCalibrationTarget = nil
            try runtime.resetTapRegionCalibration()
            state.tapRegionCalibrationDraft.reset()
            state.tapRegionCalibrationTarget = nil
            state.tapRegionCalibrationProfile = nil
            state.tapRegionCalibrationError = nil
            clearTapRegionCalibrationStoreWarning()
        } catch {
            state.tapRegionCalibrationError = error.localizedDescription
        }
    }

    private func clearTapCalibrationStoreWarning() {
        if state.recentWarning == state.tapCalibrationStoreWarning {
            state.recentWarning = nil
        }
        state.tapCalibrationStoreWarning = nil
    }

    private func clearTapRegionCalibrationStoreWarning() {
        if state.recentWarning == state.tapRegionCalibrationStoreWarning {
            state.recentWarning = nil
        }
        state.tapRegionCalibrationStoreWarning = nil
    }

    private func isAcceptedForRegionCalibration(
        _ outcome: TapFeedbackOutcome
    ) -> Bool {
        switch outcome {
        case .acceptedNonActionable, .acceptedUnmapped, .dispatchDisabled,
             .dispatched:
            return true
        case .spatialUnavailable(_, let reason):
            return reason != .tapCalibrationRequired
        case .candidate, .rejected, .duplicate:
            return false
        }
    }
}
