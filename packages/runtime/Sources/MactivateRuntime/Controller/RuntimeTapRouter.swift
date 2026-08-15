import Foundation
import MactuationCore

struct RuntimeTapEventLog {
    private var emittedIDs: Set<RuntimeEventID> = []
    private var fifo: [RuntimeEventID] = []
    private let limit: Int

    init(limit: Int) {
        self.limit = limit
    }

    mutating func reset() {
        emittedIDs.removeAll(keepingCapacity: true)
        fifo.removeAll(keepingCapacity: true)
    }

    mutating func reserve(_ eventID: RuntimeEventID) -> Bool {
        guard emittedIDs.insert(eventID).inserted else { return false }
        fifo.append(eventID)
        if fifo.count > limit {
            let overflow = fifo.count - limit
            for identifier in fifo.prefix(overflow) {
                emittedIDs.remove(identifier)
            }
            fifo.removeFirst(overflow)
        }
        return true
    }
}

struct RuntimeTapRouter {
    func route(
        _ group: TapGroup,
        resolvedAt: SensorTimestamp,
        tapCalibrationVersion: String,
        regionClassifier: TapRegionStreamClassifier,
        regionProfile: TapRegionCalibrationProfile?,
        configuration: RuntimeConfiguration,
        sessionID: UUID,
        eventLog: inout RuntimeTapEventLog,
        emit: (RuntimeOutput) -> Void
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
            rawFeatures = try regionClassifier.features(for: group)
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
        guard tapCalibrationVersion.hasPrefix("personal-") else {
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
        guard let regionProfile else {
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
        let classification = regionClassifier.classify(
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
        guard configuration.spatialTapDispatchEnabled else {
            emit(.tapFeedback(TapFeedback(
                outcome: .dispatchDisabled(gesture),
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
            sessionID: sessionID,
            classifierEventID: group.eventID(
                calibrationVersion:
                    "\(tapCalibrationVersion)|" +
                    "\(regionProfile.version)|\(side.rawValue)-" +
                    regionPattern.rawValue
            )
        )
        guard eventLog.reserve(eventID) else {
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
}
