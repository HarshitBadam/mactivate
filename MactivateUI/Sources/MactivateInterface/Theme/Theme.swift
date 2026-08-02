#if os(macOS)
import SwiftUI
import MactivateDesign

/// The bridge from design tokens to SwiftUI.
///
/// Every colour here resolves to a system colour and every font to a system text
/// style. That is the whole point of a "native Apple" target: Mactivate should
/// inherit Dark Mode, Increase Contrast, the user's accent colour, and text-size
/// preferences rather than reimplement them.
enum Theme {
    // MARK: - Colour

    static func color(for tone: Tone) -> Color {
        switch tone {
        case .neutral: return .secondary
        case .ready: return .green
        case .attention: return .orange
        case .unavailable: return .secondary
        case .failure: return .red
        case .experimental: return .purple
        }
    }

    /// Fill behind a toned badge or pill.
    static func fill(for tone: Tone) -> Color {
        color(for: tone).opacity(0.14)
    }

    static let accent = Color(nsColor: .controlAccentColor)
    static let separator = Color(nsColor: .separatorColor)
    static let primaryLabel = Color(nsColor: .labelColor)
    static let secondaryLabel = Color(nsColor: .secondaryLabelColor)
    static let tertiaryLabel = Color(nsColor: .tertiaryLabelColor)
    static let controlBackground = Color(nsColor: .controlBackgroundColor)
    static let selectionFill = Color(nsColor: .selectedContentBackgroundColor)

    // MARK: - Type

    static func font(_ role: TypeRole) -> Font {
        switch role {
        case .title: return .system(.title3, design: .default, weight: .semibold)
        case .sectionHeader: return .system(.subheadline, weight: .semibold)
        case .body: return .system(.body)
        case .bodyEmphasis: return .system(.body, weight: .medium)
        case .caption: return .system(.caption)
        case .metric: return .system(.callout, design: .rounded, weight: .medium).monospacedDigit()
        case .badge: return .system(.caption2, weight: .semibold)
        }
    }
}

extension View {
    /// A grouped-form-style card: the surface used for capability rows, binding
    /// groups, and pad pages.
    func mactivateCard(radius: CGFloat = Metrics.Radius.card, isSelected: Bool = false) -> some View {
        background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Theme.controlBackground.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(
                    isSelected ? Theme.accent : Theme.separator,
                    lineWidth: isSelected ? 2 : Metrics.Control.borderWidth
                )
        )
    }

    /// A visible focus indicator that does not rely on colour alone.
    func mactivateFocusRing(_ isFocused: Bool, radius: CGFloat = Metrics.Radius.card) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: radius + 2, style: .continuous)
                .strokeBorder(Theme.accent, lineWidth: Metrics.Control.focusRingWidth)
                .opacity(isFocused ? 1 : 0)
                .padding(-3)
        )
    }
}

// MARK: - Motion

extension Motion.Profile {
    /// The panel's reveal: a spring normally, a plain cross-fade under Reduce
    /// Motion.
    var panelAnimation: Animation {
        panelUsesSpring
            ? .spring(response: Motion.panelReveal.response, dampingFraction: Motion.panelReveal.dampingFraction)
            : .easeOut(duration: Motion.Duration.reducedMotionCrossFade)
    }

    var selectionAnimation: Animation {
        crossFadeOnly
            ? .easeOut(duration: Motion.Duration.reducedMotionCrossFade)
            : .spring(response: Motion.selection.response, dampingFraction: Motion.selection.dampingFraction)
    }

    var acknowledgementAnimation: Animation {
        .easeOut(duration: duration(Motion.Duration.acknowledgement))
    }

    var stateChangeAnimation: Animation {
        .easeInOut(duration: duration(Motion.Duration.stateChange))
    }
}

/// Reads the system Reduce Motion setting into a `Motion.Profile`.
struct MotionProfileKey: EnvironmentKey {
    static let defaultValue = Motion.Profile(reduceMotion: false)
}

extension EnvironmentValues {
    var motionProfile: Motion.Profile {
        get { self[MotionProfileKey.self] }
        set { self[MotionProfileKey.self] = newValue }
    }
}

/// Applied once, high in each surface, so every child reads one resolved profile
/// instead of re-deriving it.
struct ResolvedMotionProfile: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.environment(\.motionProfile, Motion.Profile(reduceMotion: reduceMotion))
    }
}

extension View {
    func resolvingMotionProfile() -> some View {
        modifier(ResolvedMotionProfile())
    }
}
#endif
