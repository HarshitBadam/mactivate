#if os(macOS)
import SwiftUI
import MactivateDesign

/// Live sensor trace.
///
/// Two rules make this component honest rather than decorative: it draws only
/// what the engine sends, and when the sensor is flat it says so in words instead
/// of leaving the user to interpret a straight line. Under Reduce Motion the
/// trace still updates — it is data, not animation — but nothing else moves.
struct WaveformView: View {
    let buffer: WaveformBuffer
    var tone: Tone = .ready
    var height: CGFloat = Metrics.Waveform.compactHeight
    /// Shown centred when the trace is flat.
    var silentMessage: String?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Metrics.Radius.chip, style: .continuous)
                .fill(Theme.controlBackground.opacity(0.5))

            GeometryReader { geometry in
                let points = buffer.plotPoints()
                Path { path in
                    guard points.count > 1 else { return }
                    let stepX = geometry.size.width / CGFloat(points.count - 1)
                    for (index, value) in points.enumerated() {
                        let x = CGFloat(index) * stepX
                        let y = geometry.size.height * (1 - CGFloat(value))
                        let point = CGPoint(x: x, y: y)
                        if index == 0 {
                            path.move(to: point)
                        } else {
                            path.addLine(to: point)
                        }
                    }
                }
                .stroke(
                    Theme.color(for: tone),
                    style: StrokeStyle(lineWidth: Metrics.Waveform.lineWidth, lineCap: .round, lineJoin: .round)
                )
            }
            .padding(.vertical, Metrics.Spacing.tight)
            .padding(.horizontal, Metrics.Spacing.snug)

            if buffer.isSilent, let silentMessage {
                Text(silentMessage)
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.secondaryLabel)
                    .padding(.horizontal, Metrics.Spacing.snug)
                    .background(
                        RoundedRectangle(cornerRadius: Metrics.Radius.control, style: .continuous)
                            .fill(Theme.controlBackground.opacity(0.9))
                    )
            }
        }
        .frame(height: height)
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.Radius.chip, style: .continuous)
                .strokeBorder(Theme.separator, lineWidth: Metrics.Control.borderWidth)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Live sensor signal")
        .accessibilityValue(
            buffer.isSilent
                ? (silentMessage ?? "No signal")
                : "Current level \(RelativeTime.percent(buffer.recentPeak()))"
        )
    }
}

/// Drives a `WaveformBuffer` from an `AsyncStream` for the lifetime of the view.
///
/// The stream is torn down with the view, which is what guarantees a "Test" panel
/// stops asking for sensor data — and releases a camera or microphone — the moment
/// it is closed.
struct LiveWaveform: View {
    let stream: () -> AsyncStream<Double>
    var tone: Tone = .ready
    var height: CGFloat = Metrics.Waveform.compactHeight
    var silentMessage: String?

    @State private var buffer = WaveformBuffer()

    var body: some View {
        WaveformView(buffer: buffer, tone: tone, height: height, silentMessage: silentMessage)
            .task {
                for await value in stream() {
                    buffer.append(value)
                }
            }
    }
}
#endif
