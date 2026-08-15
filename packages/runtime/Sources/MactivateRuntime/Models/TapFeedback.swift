import Foundation
import MactuationCore

public enum SpatialTapUnavailableReason: Equatable, Sendable {
    case tapCalibrationRequired
    case calibrationRequired
    case gyroscopeUnavailable
    case insufficientGyroscopeData
    case ambiguous
    case invalidProfile

    public var message: String {
        switch self {
        case .tapCalibrationRequired:
            return "tap-acceptance calibration required"
        case .calibrationRequired:
            return "left/right calibration required"
        case .gyroscopeUnavailable:
            return "gyroscope unavailable"
        case .insufficientGyroscopeData:
            return "incomplete gyroscope window"
        case .ambiguous:
            return "side was inside the confidence guard band"
        case .invalidProfile:
            return "left/right calibration is invalid"
        }
    }
}

public enum TapFeedbackOutcome: Equatable, Sendable {
    case candidate
    case rejected(TapRejectionReason)
    case acceptedNonActionable(TapPattern)
    case acceptedUnmapped(PalmTapGesture)
    case dispatchDisabled(PalmTapGesture)
    case duplicate(PalmTapGesture)
    case spatialUnavailable(pattern: TapRegionPattern,
                            reason: SpatialTapUnavailableReason)
    case dispatched(gesture: PalmTapGesture, action: ActionIdentifier)
}

public struct TapFeedback: Equatable, Sendable {
    public let outcome: TapFeedbackOutcome
    public let acceptanceVerdict: TapVerdict?
    public let memberCount: Int
    public let features: TapEventFeatures
    public let sensorTimestamp: SensorTimestamp
    public let resolutionLatencyS: Double
    public let regionPrediction: TapRegionPrediction?
    public let regionMemberFeatures: [Double]
    public let regionFeature: Double?
    public let regionProfileVersion: String?
    public let regionReason: TapRegionResolutionReason?

    public init(
        outcome: TapFeedbackOutcome,
        acceptanceVerdict: TapVerdict? = nil,
        memberCount: Int,
        features: TapEventFeatures,
        sensorTimestamp: SensorTimestamp,
        resolutionLatencyS: Double,
        regionPrediction: TapRegionPrediction? = nil,
        regionMemberFeatures: [Double] = [],
        regionFeature: Double? = nil,
        regionProfileVersion: String? = nil,
        regionReason: TapRegionResolutionReason? = nil
    ) {
        self.outcome = outcome
        self.acceptanceVerdict = acceptanceVerdict
        self.memberCount = memberCount
        self.features = features
        self.sensorTimestamp = sensorTimestamp
        self.resolutionLatencyS = resolutionLatencyS
        self.regionPrediction = regionPrediction
        self.regionMemberFeatures = regionMemberFeatures
        self.regionFeature = regionFeature
        self.regionProfileVersion = regionProfileVersion
        self.regionReason = regionReason
    }
}
