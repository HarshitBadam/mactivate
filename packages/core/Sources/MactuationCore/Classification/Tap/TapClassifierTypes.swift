import Foundation

/// Impulses are stored in mg·s (the unit the documented cuts are stated in).
public struct TapEventFeatures: Equatable, Sendable {
    public var time: SensorTimestamp
    public var peakG: Double
    public var decayMs: Double
    /// Signed Z ±25 ms impulse (mg·s); positive is the palm-tap signature.
    public var zImpulseMgS: Double
    /// Absolute lateral ±25 ms impulse |x|+|y| (mg·s); the bump discriminator.
    public var lateralImpulseMgS: Double

    public init(
        time: SensorTimestamp,
        peakG: Double,
        decayMs: Double,
        zImpulseMgS: Double,
        lateralImpulseMgS: Double
    ) {
        self.time = time
        self.peakG = peakG
        self.decayMs = decayMs
        self.zImpulseMgS = zImpulseMgS
        self.lateralImpulseMgS = lateralImpulseMgS
    }
}

public enum TapVerdict: Equatable, Sendable {
    case acceptedComfort
    /// The side names the amplitude-calibration entry that matched; spatial
    /// side is resolved separately from the gyroscope.
    case acceptedFirm(PalmSide)
    case rejected

    public var isAccepted: Bool {
        if case .rejected = self { return false }
        return true
    }
}

public enum TapRejectionReason: String, Codable, Equatable, Sendable {
    case noMembers
    case tooManyMembers
    case firmLateralImpulse
    case firmDecay
    case comfortZImpulse
    case comfortLateralImpulse

    public var guidance: String {
        switch self {
        case .noMembers:
            return "No complete tap impulse was measured."
        case .tooManyMembers:
            return "The tap rang through the chassis as too many impacts; use a lighter touch."
        case .firmLateralImpulse:
            return "The movement looked more like a desk bump than a palm-rest tap."
        case .firmDecay:
            return "The impact rang for too long; use a shorter, lighter tap."
        case .comfortZImpulse:
            return "The impulse direction did not match a calibrated palm-rest tap."
        case .comfortLateralImpulse:
            return "The movement contained too much sideways chassis motion."
        }
    }
}

public struct TapGroup: Equatable, Sendable {
    public var members: [TapEventFeatures]
    public var verdict: TapVerdict
    public var rejectionReason: TapRejectionReason?

    public init(
        members: [TapEventFeatures],
        verdict: TapVerdict,
        rejectionReason: TapRejectionReason? = nil
    ) {
        self.members = members
        self.verdict = verdict
        self.rejectionReason = rejectionReason
    }

    /// Stable identifier: the calibration version plus the first member's
    /// exact peak timestamp. Identical input and calibration reproduce it
    /// exactly; the action layer deduplicates dispatch on it.
    public func eventID(calibrationVersion: String) -> String {
        "\(calibrationVersion)/\(encodeRoundTrippable(members[0].time))"
    }
}

struct TapClassifierAnalysis {
    var groups: [TapGroup]
    var candidates: [TapEventFeatures]
    var resolvedThrough: SensorTimestamp?
}
