#if os(macOS)
import SwiftUI
import MactivateDesign

/// The device map: a top-down MacBook on a desk with the tap regions drawn where
/// they physically are.
///
/// This is the one genuinely spatial thing in the product, so it is direct
/// manipulation — you point at the place you tap. It is never the *only* way to
/// reach a region though: the Taps screen lists the same regions, because a map is
/// not keyboard- or VoiceOver-friendly on its own no matter how carefully it is
/// labelled.
struct DeviceMapView: View {
    let regions: [TapRegion]
    let boundCounts: [TapRegionID: Int]
    @Binding var selection: TapRegionID?
    /// Briefly highlighted when a tap is accepted there, so the map doubles as
    /// live feedback that the right region fired.
    var flashingRegion: TapRegionID?
    var isCompact = false

    @Environment(\.motionProfile) private var motion

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack(alignment: .topLeading) {
                deskSurface
                lid(in: size)
                deck(in: size)
                trackpad(in: size)

                ForEach(regions) { region in
                    regionButton(region, in: size)
                }
            }
        }
        .aspectRatio(1.5, contentMode: .fit)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tap regions on your MacBook and desk")
    }

    private var deskSurface: some View {
        RoundedRectangle(cornerRadius: Metrics.Radius.card, style: .continuous)
            .fill(Theme.controlBackground.opacity(0.45))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.Radius.card, style: .continuous)
                    .strokeBorder(Theme.separator, lineWidth: Metrics.Control.borderWidth)
            )
    }

    private func lid(in size: CGSize) -> some View {
        let frame = rect(DeviceMapLayout.lid, in: size)
        return ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: Metrics.Radius.chip, style: .continuous)
                .fill(Theme.controlBackground.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.Radius.chip, style: .continuous)
                        .strokeBorder(Theme.separator, lineWidth: Metrics.Control.borderWidth)
                )
            // The notch, drawn because it is where the hand wave happens.
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Theme.primaryLabel.opacity(0.55))
                .frame(width: max(18, frame.width * 0.18), height: max(4, frame.height * 0.13))
        }
        .frame(width: frame.width, height: frame.height)
        .offset(x: frame.minX, y: frame.minY)
        .accessibilityHidden(true)
    }

    private func deck(in size: CGSize) -> some View {
        let frame = rect(DeviceMapLayout.deck, in: size)
        return RoundedRectangle(cornerRadius: Metrics.Radius.chip, style: .continuous)
            .fill(Theme.controlBackground.opacity(0.7))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.Radius.chip, style: .continuous)
                    .strokeBorder(Theme.separator, lineWidth: Metrics.Control.borderWidth)
            )
            .frame(width: frame.width, height: frame.height)
            .offset(x: frame.minX, y: frame.minY)
            .accessibilityHidden(true)
    }

    private func trackpad(in size: CGSize) -> some View {
        let frame = rect(DeviceMapLayout.trackpad, in: size)
        return RoundedRectangle(cornerRadius: Metrics.Radius.control, style: .continuous)
            .strokeBorder(Theme.tertiaryLabel, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .frame(width: frame.width, height: frame.height)
            .offset(x: frame.minX, y: frame.minY)
            .accessibilityHidden(true)
    }

    private func regionButton(_ region: TapRegion, in size: CGSize) -> some View {
        let frame = rect(region.frame, in: size)
        let isSelected = selection == region.id
        let isFlashing = flashingRegion == region.id
        let bound = boundCounts[region.id] ?? 0
        let tone = region.calibration.tone
        let isUsable = region.calibration.allowsBindings

        return Button {
            withAnimation(motion.selectionAnimation) { selection = region.id }
        } label: {
            VStack(spacing: 2) {
                if !isCompact {
                    Text(region.name)
                        .font(Theme.font(.badge))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                if isUsable {
                    Text(bound == 0 ? "Not set" : "\(bound) of 3")
                        .font(Theme.font(.badge))
                        .foregroundStyle(Theme.secondaryLabel)
                } else {
                    Image(systemName: "slash.circle")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.secondaryLabel)
                }
            }
            .padding(2)
            .frame(width: frame.width, height: frame.height)
            .background(
                RoundedRectangle(cornerRadius: Metrics.Radius.control, style: .continuous)
                    .fill(
                        isFlashing
                            ? Theme.color(for: .ready).opacity(0.5)
                            : (isSelected ? Theme.accent.opacity(0.22) : Theme.fill(for: tone))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.Radius.control, style: .continuous)
                    .strokeBorder(
                        isSelected ? Theme.accent : Theme.color(for: tone).opacity(isUsable ? 0.5 : 0.3),
                        style: StrokeStyle(
                            lineWidth: isSelected ? 2 : 1,
                            dash: isUsable ? [] : [3, 2]
                        )
                    )
            )
        }
        .buttonStyle(.plain)
        .offset(x: frame.minX, y: frame.minY)
        .animation(motion.acknowledgementAnimation, value: isFlashing)
        .help(regionHelp(region, bound: bound))
        .accessibilityLabel(region.accessibilityLabel)
        .accessibilityValue(accessibilityValue(region, bound: bound))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func regionHelp(_ region: TapRegion, bound: Int) -> String {
        switch region.calibration {
        case .unsupported(let reason): return reason
        case .uncalibrated: return "\(region.name) — not calibrated yet"
        case .lowConfidence: return "\(region.name) — calibrated, but unreliable here"
        case .calibrated: return "\(region.name) — \(bound) of 3 taps mapped"
        }
    }

    private func accessibilityValue(_ region: TapRegion, bound: Int) -> String {
        switch region.calibration {
        case .unsupported(let reason): return "Unavailable. \(reason)"
        case .uncalibrated: return "Not calibrated. \(bound) of 3 taps mapped."
        case .lowConfidence(let recall, _, _):
            return "Low confidence, \(RelativeTime.percent(recall)) detected. \(bound) of 3 taps mapped."
        case .calibrated(let recall, _, _):
            return "Calibrated, \(RelativeTime.percent(recall)) detected. \(bound) of 3 taps mapped."
        }
    }

    private func rect(_ normalized: NormalizedRect, in size: CGSize) -> CGRect {
        CGRect(
            x: normalized.x * size.width,
            y: normalized.y * size.height,
            width: normalized.width * size.width,
            height: normalized.height * size.height
        )
    }
}
#endif
