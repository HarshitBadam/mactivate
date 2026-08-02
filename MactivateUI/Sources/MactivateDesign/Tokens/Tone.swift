import Foundation

/// Semantic status tone. The view layer maps each case to a system colour
/// (`.secondaryLabel`, `.systemGreen`, `.systemOrange`, `.systemRed`,
/// `.systemPurple`) so Mactivate never ships a bespoke palette and inherits
/// Increase Contrast, Dark Mode, and accent-colour behaviour for free.
///
/// Tone is never the only carrier of meaning: every toned element also has a
/// symbol and a text label, which is what keeps the surfaces readable for
/// colour-blind users and in VoiceOver.
public enum Tone: String, Codable, CaseIterable, Sendable {
    /// Nothing to report; informational.
    case neutral
    /// Working as intended, validated locally.
    case ready
    /// Usable but needs the user: permission, opt-in, calibration.
    case attention
    /// Not usable right now. A first-class state, not an error.
    case unavailable
    /// Something failed and the user should know: action error, helper lost.
    case failure
    /// Unvalidated on this machine — hypothesis, not a promise.
    case experimental
}

/// Semantic text roles, mapped to system text styles in the view layer so
/// Dynamic-Type-like scaling and VoiceOver rotor behaviour stay standard.
public enum TypeRole: String, Sendable {
    /// Panel and window titles.
    case title
    /// Section headers inside a grouped form.
    case sectionHeader
    /// Row titles, button labels.
    case body
    /// Emphasised row titles.
    case bodyEmphasis
    /// Secondary explanation under a row.
    case caption
    /// Numeric read-outs: confidence, sample counts, lux.
    case metric
    /// Small uppercase status text in pills.
    case badge
}
