#if os(macOS)
import SwiftUI
import MactivateDesign

/// One binding: tap count on the left, the action in the middle, controls on the
/// right.
///
/// The row is a row — not a card, not a custom control — because this is exactly
/// the shape macOS uses for "attribute: value" editing, and users already know
/// that the trailing control is where the change happens.
struct BindingRow: View {
    let binding: TapBinding
    /// Nil when the region cannot be used at all, which greys the row and
    /// explains itself instead of offering an edit that would do nothing.
    let unavailableReason: String?
    var isFlashing = false
    let edit: () -> Void
    let clear: () -> Void
    let setEnabled: (Bool) -> Void

    @Environment(\.motionProfile) private var motion

    private var isDisabled: Bool { unavailableReason != nil }

    var body: some View {
        HStack(spacing: Metrics.Spacing.regular) {
            Label {
                Text(binding.count.shortName)
                    .font(Theme.font(.body))
            } icon: {
                Image(systemName: binding.count.symbolName)
                    .foregroundStyle(isDisabled ? Theme.tertiaryLabel : Theme.secondaryLabel)
            }
            .frame(width: 96, alignment: .leading)

            actionButton

            Spacer(minLength: Metrics.Spacing.snug)

            if binding.isBound, !isDisabled {
                Toggle("On", isOn: Binding(get: { binding.isEnabled }, set: setEnabled))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .help(binding.isEnabled ? "Turn this binding off" : "Turn this binding on")
                    .accessibilityLabel("\(binding.count.displayName) enabled")

                Button(role: .destructive, action: clear) {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .help("Remove this action")
                .accessibilityLabel("Remove the action on \(binding.count.displayName)")
            }
        }
        .padding(.vertical, Metrics.Spacing.snug)
        .padding(.horizontal, Metrics.Spacing.regular)
        .background(
            RoundedRectangle(cornerRadius: Metrics.Radius.chip, style: .continuous)
                .fill(isFlashing ? Theme.color(for: .ready).opacity(0.18) : Color.clear)
        )
        .animation(motion.acknowledgementAnimation, value: isFlashing)
        .opacity(binding.isEnabled ? 1 : 0.55)
    }

    @ViewBuilder
    private var actionButton: some View {
        if let unavailableReason {
            Text(unavailableReason)
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.secondaryLabel)
                .lineLimit(2)
        } else {
            Button(action: edit) {
                if let action = binding.action {
                    ActionChip(action: action, isMuted: !binding.isEnabled)
                } else {
                    HStack(spacing: Metrics.Spacing.tight) {
                        Image(systemName: "plus.circle.dashed")
                        Text("Choose an action")
                    }
                    .font(Theme.font(.body))
                    .foregroundStyle(Theme.secondaryLabel)
                }
            }
            .buttonStyle(.plain)
            .help(binding.action == nil ? "Pick what this tap should do" : "Change what this tap does")
            .accessibilityLabel(
                binding.action.map { "\(binding.count.displayName): \($0.title). Change" }
                    ?? "\(binding.count.displayName): nothing set. Choose an action"
            )
        }
    }
}

/// The action as a compact chip: symbol, name, and — when there is room — its
/// target. Also used on macro-pad rows and in the activity feed.
struct ActionChip: View {
    let action: ActionSpec
    var isMuted = false
    var showsDetail = true

    var body: some View {
        HStack(spacing: Metrics.Spacing.snug) {
            Image(systemName: action.symbolName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isMuted ? Theme.secondaryLabel : Theme.accent)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 0) {
                Text(action.title)
                    .font(Theme.font(.body))
                    .lineLimit(1)
                if showsDetail, let detail = action.detail, detail != action.title {
                    Text(detail)
                        .font(Theme.font(.caption))
                        .foregroundStyle(Theme.secondaryLabel)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            if !action.isRunnable {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.color(for: .attention))
                    .help(
                        action.kind == .unrecognized
                            ? "This action came from a newer version of Mactivate and will not run here."
                            : "This action is missing something it needs, so it will not run."
                    )
            }
        }
        .padding(.horizontal, Metrics.Spacing.snug)
        .padding(.vertical, Metrics.Spacing.tight)
        .background(
            RoundedRectangle(cornerRadius: Metrics.Radius.chip, style: .continuous)
                .fill(Theme.controlBackground.opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.Radius.chip, style: .continuous)
                .strokeBorder(Theme.separator, lineWidth: Metrics.Control.borderWidth)
        )
    }
}
#endif
