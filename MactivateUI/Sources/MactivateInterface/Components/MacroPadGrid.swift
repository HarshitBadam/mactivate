#if os(macOS)
import SwiftUI
import MactivateDesign

/// The macro pad: a grid of buttons that run their action on click.
///
/// It is the part of Mactivate that works on any Mac, in any state, with no
/// calibration — so it is also the honest fallback when tap sensing turns out to
/// be unavailable. Buttons look like keycaps rather than list rows because they
/// are pressed, not read.
struct MacroPadGrid: View {
    let page: MacroPadPage
    var isEditing = false
    /// Slot currently running, for the press acknowledgement.
    var runningSlotID: UUID?
    let run: (MacroPadSlot) -> Void
    let edit: (Int) -> Void

    @Environment(\.motionProfile) private var motion

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(minimum: Metrics.Control.padMinSide), spacing: Metrics.Spacing.snug),
            count: MacroPad.columns
        )
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: Metrics.Spacing.snug) {
            ForEach(Array(page.slots.enumerated()), id: \.element.id) { index, slot in
                MacroPadButton(
                    slot: slot,
                    isEditing: isEditing,
                    isRunning: runningSlotID == slot.id,
                    action: {
                        if isEditing || slot.isEmpty {
                            edit(index)
                        } else {
                            run(slot)
                        }
                    },
                    editAction: { edit(index) }
                )
            }
        }
        .animation(motion.selectionAnimation, value: page.slots.map(\.id))
    }
}

struct MacroPadButton: View {
    let slot: MacroPadSlot
    var isEditing: Bool
    var isRunning: Bool
    let action: () -> Void
    let editAction: () -> Void

    @State private var isHovering = false
    @Environment(\.motionProfile) private var motion

    var body: some View {
        Button(action: action) {
            VStack(spacing: Metrics.Spacing.tight) {
                Image(systemName: slot.symbolName)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(foregroundTint)
                Text(slot.displayLabel)
                    .font(Theme.font(.badge))
                    .foregroundStyle(slot.isEmpty ? Theme.secondaryLabel : Theme.primaryLabel)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
            }
            .padding(Metrics.Spacing.snug)
            .frame(maxWidth: .infinity, minHeight: Metrics.Control.padMinSide)
            .background(background)
            .overlay(border)
            .overlay(alignment: .topTrailing) {
                if isEditing, !slot.isEmpty {
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.accent)
                        .padding(3)
                }
            }
            .scaleEffect(isRunning && !motion.crossFadeOnly ? 0.96 : 1)
            .animation(motion.acknowledgementAnimation, value: isRunning)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .contextMenu {
            Button(slot.isEmpty ? "Add Action…" : "Edit Action…", action: editAction)
        }
        .help(helpText)
        .accessibilityLabel(slot.isEmpty ? "Empty macro pad button" : slot.displayLabel)
        .accessibilityHint(
            slot.isEmpty
                ? "Adds an action to this button"
                : (isEditing ? "Edits this button" : "Runs \(slot.action?.title ?? slot.displayLabel)")
        )
    }

    private var foregroundTint: Color {
        if slot.isEmpty { return Theme.tertiaryLabel }
        return isRunning ? Theme.color(for: .ready) : Theme.accent
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: Metrics.Radius.pad, style: .continuous)
            .fill(
                slot.isEmpty
                    ? Color.clear
                    : Theme.controlBackground.opacity(isHovering ? 0.95 : 0.7)
            )
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: Metrics.Radius.pad, style: .continuous)
            .strokeBorder(
                slot.isEmpty ? Theme.separator : (isHovering ? Theme.accent.opacity(0.6) : Theme.separator),
                style: StrokeStyle(lineWidth: 1, dash: slot.isEmpty ? [4, 3] : [])
            )
    }

    private var helpText: String {
        if slot.isEmpty { return "Add an action to this button" }
        guard let action = slot.action else { return slot.displayLabel }
        return action.detail.map { "\(action.title) — \($0)" } ?? action.title
    }
}
#endif
