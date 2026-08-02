#if os(macOS)
import SwiftUI
import MactivateDesign

/// The brief confirmation shown when a gesture is accepted.
///
/// It exists because an invisible action is indistinguishable from a broken one.
/// It appears only for accepted events, never for rejected ones — a gesture the
/// engine failed closed on must produce no feedback at all, otherwise users learn
/// to trust it and tap harder.
struct AcknowledgementBanner: View {
    let entry: ActivityEntry

    @Environment(\.motionProfile) private var motion

    var body: some View {
        HStack(spacing: Metrics.Spacing.snug) {
            Image(systemName: entry.outcome == .ran ? "checkmark.circle.fill" : entry.symbolName)
                .foregroundStyle(Theme.color(for: entry.outcome.tone))
            VStack(alignment: .leading, spacing: 0) {
                Text(entry.actionTitle ?? gestureDescription)
                    .font(Theme.font(.bodyEmphasis))
                    .lineLimit(1)
                if let detail = outcomeDetail {
                    Text(detail)
                        .font(Theme.font(.caption))
                        .foregroundStyle(Theme.secondaryLabel)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, Metrics.Spacing.regular)
        .padding(.vertical, Metrics.Spacing.snug)
        .background(
            Capsule(style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            Capsule(style: .continuous).strokeBorder(Theme.separator, lineWidth: Metrics.Control.borderWidth)
        )
        .shadow(color: .black.opacity(0.16), radius: 8, y: 3)
        .transition(
            motion.crossFadeOnly
                ? .opacity
                : .asymmetric(insertion: .scale(scale: 0.94).combined(with: .opacity), removal: .opacity)
        )
        // Announced rather than focused, so the acknowledgement never steals the
        // user's place in whatever they were doing.
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var gestureDescription: String {
        switch entry.event.kind {
        case .tap(_, let count): return "\(count.displayName) recognized"
        case .handNear: return "Hand wave recognized"
        case .macroPad: return "Button pressed"
        case .hotkey: return "Shortcut pressed"
        }
    }

    private var outcomeDetail: String? {
        switch entry.outcome {
        case .ran: return nil
        case .noBinding: return "Nothing is mapped to that yet"
        case .skippedPaused: return "Mactivate is paused, so nothing ran"
        case .failed(let reason): return reason
        }
    }
}

/// One row of the recent-activity list.
struct ActivityRow: View {
    let entry: ActivityEntry
    var showsConfidence = true

    var body: some View {
        HStack(spacing: Metrics.Spacing.regular) {
            Image(systemName: entry.symbolName)
                .font(.system(size: 12))
                .foregroundStyle(Theme.color(for: entry.outcome.tone))
                .frame(width: 18)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.actionTitle ?? gestureTitle)
                    .font(Theme.font(.body))
                    .lineLimit(1)
                Text(subtitle)
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.secondaryLabel)
                    .lineLimit(1)
            }

            Spacer(minLength: Metrics.Spacing.snug)

            if showsConfidence, case .tap = entry.event.kind {
                Text(RelativeTime.percent(entry.event.confidence))
                    .font(Theme.font(.metric))
                    .foregroundStyle(Theme.secondaryLabel)
                    .help("How confident the engine was in this tap")
            }

            Text(RelativeTime.short(from: entry.event.timestamp))
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.tertiaryLabel)
                .frame(width: 62, alignment: .trailing)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.actionTitle ?? gestureTitle)
        .accessibilityValue("\(subtitle), \(RelativeTime.spoken(from: entry.event.timestamp))")
    }

    private var gestureTitle: String {
        switch entry.event.kind {
        case .tap(_, let count): return count.displayName
        case .handNear: return "Hand wave"
        case .macroPad: return "Macro pad button"
        case .hotkey: return "Keyboard shortcut"
        }
    }

    private var subtitle: String {
        switch entry.outcome {
        case .ran: return gestureTitle
        case .noBinding: return "\(gestureTitle) — nothing mapped"
        case .skippedPaused: return "\(gestureTitle) — paused, nothing ran"
        case .failed(let reason): return reason
        }
    }
}

/// The calibration read-out: the measured numbers, the verdict against the
/// project's qualification bar, and what to do next.
struct ConfidenceReadout: View {
    let result: CalibrationResult

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.Spacing.snug) {
            HStack(spacing: Metrics.Spacing.snug) {
                Image(systemName: result.meetsQualificationBar ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.color(for: result.tone))
                Text(result.readout)
                    .font(Theme.font(.bodyEmphasis))
            }

            HStack(spacing: Metrics.Spacing.section) {
                metric("Detected", RelativeTime.percent(result.recall))
                metric("False fires", "\(result.falseFires)")
                metric("Bar", "95% and none")
            }

            Text(result.recommendation)
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)

            if let note = result.note {
                Text(note)
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.tertiaryLabel)
            }
        }
        .padding(Metrics.Spacing.regular)
        .mactivateCard()
        .accessibilityElement(children: .combine)
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(Theme.font(.metric))
            Text(label).font(Theme.font(.badge)).foregroundStyle(Theme.secondaryLabel)
        }
    }
}
#endif
