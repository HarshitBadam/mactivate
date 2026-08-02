import Foundation

/// Palm-rest side, used as a *calibration provenance label* only. H-TAP-REGION
/// is refuted on the target machine (no per-tap lateral localization exists —
/// see docs/research/gesture-hypotheses.md), so the classifier can never
/// attribute a detected tap to a side at runtime. Per-side entries record
/// independently learned cuts; acceptance tests each configured side's tier.
public enum PalmSide: String, Codable, CaseIterable, Sendable, Comparable {
    case left
    case right

    public static func < (lhs: PalmSide, rhs: PalmSide) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Versioned configuration of the H-TAP-PALM tiered rule. Every numeric field
/// is part of the deterministic-replay contract: identical samples plus an
/// identical calibration (same `version`, same values) must classify
/// identically, byte for byte.
///
/// The values in `mac14_2Discovery` are the ones measured and validated in
/// docs/probe-results/2026-07-24-mac14-2-discovery.md; they are not tunable
/// defaults. Changing any value requires a new `version` string and fresh
/// measured fixtures.
public struct TapCalibration: Codable, Equatable, Sendable {
    /// Amplitude tier for very firm taps whose chassis ring-down breaks the
    /// comfort tier's Z-impulse gate. Its bump veto is *scaled*: firm palm
    /// taps carry large absolute lateral impulse, so the veto bounds the
    /// lateral-to-peak ratio and the decay instead of the absolute lateral.
    public struct FirmTier: Codable, Equatable, Sendable {
        /// First-member detrended-magnitude peak must reach this (g).
        public var amplitudeCutG: Double
        /// Reject when lateral ±25 ms impulse / peak exceeds this ((mg·s)/g).
        public var lateralToPeakMaxMgSPerG: Double
        /// Reject when the envelope takes longer than this to fall below
        /// half-threshold after the peak (ms).
        public var decayMaxMs: Double

        public init(amplitudeCutG: Double, lateralToPeakMaxMgSPerG: Double, decayMaxMs: Double) {
            self.amplitudeCutG = amplitudeCutG
            self.lateralToPeakMaxMgSPerG = lateralToPeakMaxMgSPerG
            self.decayMaxMs = decayMaxMs
        }
    }

    public var version: String

    /// Centered moving-average high-pass window (s). The validated rule is
    /// defined on this *centered* detrend, so classification of a sample needs
    /// half a window of lookahead — a live adapter must buffer accordingly.
    public var detrendWindowS: Double
    /// Onset threshold on the detrended magnitude (g).
    public var eventThresholdG: Double
    /// Refractory window after each event peak (s).
    public var refractoryS: Double
    /// Maximum gap between successive events of one group (s).
    public var groupGapS: Double
    /// Groups larger than this are rejected outright (1–3 taps are gestures).
    public var maxGroupMembers: Int
    /// Half-width of the signed per-axis impulse window around a peak (s).
    public var impulseHalfWindowS: Double

    /// Comfort-tier bump veto: reject when the first member's absolute lateral
    /// ±25 ms impulse (|x|+|y|, mg·s) is at or above this. Validated on two
    /// independently composed bump takes; the measured margin is thin
    /// (palm max 0.216 vs bump min 0.251 mg·s).
    public var comfortLateralVetoMgS: Double

    /// Firm tiers keyed by the palm side they were calibrated on. A missing
    /// side means "not yet calibrated" — its firm taps are covered only by
    /// whatever other tiers accept them (the measured state of the right side).
    public var firmTiers: [PalmSide: FirmTier]

    public init(version: String, detrendWindowS: Double, eventThresholdG: Double,
                refractoryS: Double, groupGapS: Double, maxGroupMembers: Int,
                impulseHalfWindowS: Double, comfortLateralVetoMgS: Double,
                firmTiers: [PalmSide: FirmTier]) {
        self.version = version
        self.detrendWindowS = detrendWindowS
        self.eventThresholdG = eventThresholdG
        self.refractoryS = refractoryS
        self.groupGapS = groupGapS
        self.maxGroupMembers = maxGroupMembers
        self.impulseHalfWindowS = impulseHalfWindowS
        self.comfortLateralVetoMgS = comfortLateralVetoMgS
        self.firmTiers = firmTiers
    }

    /// The rule exactly as validated on Mac14,2 / macOS 26.2 on 2026-07-24.
    /// Only the left palm rest has a qualified firm-tier amplitude cut; the
    /// right side's cut was measured as necessary but never established
    /// (right-firm recall under this calibration is the documented 75%).
    public static let mac14_2Discovery = TapCalibration(
        version: "mac14_2-20260724-left-calibrated-1",
        detrendWindowS: 0.5,
        eventThresholdG: 0.04,
        refractoryS: 0.15,
        groupGapS: 1.0,
        maxGroupMembers: 3,
        impulseHalfWindowS: 0.025,
        comfortLateralVetoMgS: 0.25,
        firmTiers: [.left: FirmTier(amplitudeCutG: 0.25,
                                    lateralToPeakMaxMgSPerG: 5,
                                    decayMaxMs: 150)])
}
