#if os(macOS)
import SwiftUI
import MactivateDesign

/// A small state badge: symbol, label, tone. Used in the panel header, the
/// sidebar, and capability rows.
///
/// The symbol is not decoration — it is the redundant channel that keeps the
/// state legible without colour, which is why it is never optional here.
struct StatusPill: View {
    let symbolName: String
    let title: String
    let tone: Tone
    var isCompact = false

    var body: some View {
        HStack(spacing: Metrics.Spacing.tight) {
            Image(systemName: symbolName)
                .font(.system(size: isCompact ? 9 : 10, weight: .semibold))
            Text(title)
                .font(Theme.font(isCompact ? .badge : .caption))
                .lineLimit(1)
        }
        .foregroundStyle(Theme.color(for: tone))
        .padding(.horizontal, isCompact ? Metrics.Spacing.snug : Metrics.Spacing.regular)
        .padding(.vertical, isCompact ? 3 : Metrics.Spacing.tight)
        .background(
            Capsule(style: .continuous).fill(Theme.fill(for: tone))
        )
        .overlay(
            Capsule(style: .continuous).strokeBorder(Theme.color(for: tone).opacity(0.28), lineWidth: 0.5)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }
}

/// A short explanatory block with a symbol: used for permission explainers,
/// privacy notes, and empty states. Deliberately not an alert — these are things
/// the user should read in place, not dismiss.
struct ExplainerCallout: View {
    let symbolName: String
    let title: String
    let message: String
    var tone: Tone = .neutral
    var primaryActionTitle: String?
    var primaryAction: (() -> Void)?
    var secondaryActionTitle: String?
    var secondaryAction: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: Metrics.Spacing.regular) {
            Image(systemName: symbolName)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.color(for: tone))
                .frame(width: 20)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Metrics.Spacing.tight) {
                Text(title)
                    .font(Theme.font(.bodyEmphasis))
                Text(message)
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)

                if primaryActionTitle != nil || secondaryActionTitle != nil {
                    HStack(spacing: Metrics.Spacing.snug) {
                        if let primaryActionTitle, let primaryAction {
                            Button(primaryActionTitle, action: primaryAction)
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                        }
                        if let secondaryActionTitle, let secondaryAction {
                            Button(secondaryActionTitle, action: secondaryAction)
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                    .padding(.top, Metrics.Spacing.tight)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Metrics.Spacing.regular)
        .background(
            RoundedRectangle(cornerRadius: Metrics.Radius.card, style: .continuous)
                .fill(Theme.fill(for: tone))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.Radius.card, style: .continuous)
                .strokeBorder(Theme.color(for: tone).opacity(0.22), lineWidth: Metrics.Control.borderWidth)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityHint(message)
    }
}

/// The standard "nothing here yet" state: symbol, one line of what this is for,
/// and the single action that fills it.
struct EmptyStateView: View {
    let symbolName: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: Metrics.Spacing.regular) {
            Image(systemName: symbolName)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Theme.tertiaryLabel)
                .accessibilityHidden(true)
            VStack(spacing: Metrics.Spacing.tight) {
                Text(title).font(Theme.font(.bodyEmphasis))
                Text(message)
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.secondaryLabel)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: 320)
        .padding(Metrics.Spacing.section)
        .accessibilityElement(children: .combine)
    }
}
#endif
