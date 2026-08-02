import Foundation

/// Named motion for the surfaces, expressed as data so the reduced-motion rule
/// is enforced in one place instead of at every animation call site.
///
/// The notch panel is the one surface where motion carries meaning: it must read
/// as *pulled down from the notch*, so it animates its height with a spring
/// while the notch itself stays anchored. Everything else uses short, plain
/// easing, and all of it collapses to a cross-fade when Reduce Motion is on.
public enum Motion {
    public struct Spring: Equatable, Sendable {
        public var response: Double
        public var dampingFraction: Double

        public init(response: Double, dampingFraction: Double) {
            self.response = response
            self.dampingFraction = dampingFraction
        }
    }

    /// The pull-down/retract of the notch panel.
    public static let panelReveal = Spring(response: 0.34, dampingFraction: 0.82)
    /// Selecting a tap region or a macro-pad page.
    public static let selection = Spring(response: 0.24, dampingFraction: 0.9)

    public enum Duration {
        /// Feedback that must land before the user's next glance: tap accepted,
        /// action fired.
        public static let acknowledgement: Double = 0.16
        public static let stateChange: Double = 0.22
        /// Cross-fade substituted for every animation under Reduce Motion.
        public static let reducedMotionCrossFade: Double = 0.12
        /// How long an accepted-gesture acknowledgement stays on screen.
        public static let acknowledgementHold: Double = 1.4
    }

    /// Resolved motion for a surface, given the system Reduce Motion setting.
    public struct Profile: Equatable, Sendable {
        public var reduceMotion: Bool

        public init(reduceMotion: Bool) {
            self.reduceMotion = reduceMotion
        }

        /// Reduce Motion replaces geometry animation with opacity, so the panel
        /// must not spring, slide, or scale.
        public var panelUsesSpring: Bool { !reduceMotion }

        public var crossFadeOnly: Bool { reduceMotion }

        public func duration(_ base: Double) -> Double {
            reduceMotion ? Duration.reducedMotionCrossFade : base
        }
    }
}
