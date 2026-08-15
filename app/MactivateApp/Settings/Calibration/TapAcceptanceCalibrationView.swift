import MactivateRuntime
import SwiftUI

struct TapAcceptanceCalibrationView: View {
    @ObservedObject var state: AppState
    let actions: SettingsActions

    private let targets = [
        TapCalibrationTarget(side: .left, intensity: .comfort),
        TapCalibrationTarget(side: .left, intensity: .firm),
        TapCalibrationTarget(side: .right, intensity: .comfort),
        TapCalibrationTarget(side: .right, intensity: .firm)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.cardInset) {
            stepHeader
            ProgressView(
                value: Double(totalSampleCount),
                total: Double(
                    targets.count *
                        TapCalibrationDraft.requiredSamplesPerTarget
                )
            )
            .accessibilityLabel("Tap acceptance calibration progress")

            Text(
                "Keep the Mac on a stable surface. Choose a row, then tap at " +
                    "your own pace. Invalid impacts do not count."
            )
            .font(.callout)
            .foregroundStyle(.secondary)

            VStack(spacing: SettingsMetrics.iconGap) {
                ForEach(targets, id: \.self) { target in
                    captureRow(target)
                }
            }

            if let feedback = state.lastTapFeedback,
               feedback.outcome == .candidate {
                Label(
                    "Determining the tap count.",
                    systemImage: "waveform"
                )
                .font(.callout)
                .foregroundStyle(Color.accentColor)
            }

            if let error = state.tapCalibrationError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            HStack {
                if state.tapCalibrationTarget != nil {
                    Button(
                        "Pause capture",
                        action: actions.stopCalibrationCapture
                    )
                }
                Spacer()
                Button("Save Step 1", action: actions.saveCalibration)
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        !isComplete || state.tapCalibrationTarget != nil
                    )
            }
            .padding(.horizontal, SettingsMetrics.fieldGap)
        }
    }

    private func captureRow(_ target: TapCalibrationTarget) -> some View {
        let count = state.tapCalibrationDraft.sampleCount(
            side: target.side,
            intensity: target.intensity
        )
        let isActive = state.tapCalibrationTarget == target
        let isDone = count >= TapCalibrationDraft.requiredSamplesPerTarget
        return HStack(spacing: SettingsMetrics.controlGap) {
            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isDone ? .primary : .secondary)
            Text("\(target.side.rawValue.capitalized) \(target.intensity.rawValue.capitalized)")
            Spacer()
            Text(
                "\(count)/\(TapCalibrationDraft.requiredSamplesPerTarget)"
            )
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Button(
                isActive ? "Capturing…" : isDone ? "Redo" : "Capture"
            ) {
                actions.beginCalibrationCapture(target)
            }
            .disabled(isActive)
        }
        .padding(.horizontal, SettingsMetrics.fieldGap)
        .frame(minHeight: SettingsMetrics.rowHeight)
        .background(
            isActive
                ? Color.accentColor.opacity(0.12)
                : Color(nsColor: .textBackgroundColor),
            in: RoundedRectangle(cornerRadius: 6)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "\(target.side.rawValue) \(target.intensity.rawValue), " +
                "\(count) of \(TapCalibrationDraft.requiredSamplesPerTarget)"
        )
        .accessibilityIdentifier(
            "calibration-capture-\(target.side.rawValue)-" +
                target.intensity.rawValue
        )
    }

    private var isComplete: Bool {
        targets.allSatisfy {
            state.tapCalibrationDraft.sampleCount(
                side: $0.side,
                intensity: $0.intensity
            ) >= TapCalibrationDraft.requiredSamplesPerTarget
        }
    }

    private var totalSampleCount: Int {
        targets.reduce(0) {
            $0 + state.tapCalibrationDraft.sampleCount(
                side: $1.side,
                intensity: $1.intensity
            )
        }
    }

    private var stepHeader: some View {
        HStack(spacing: SettingsMetrics.fieldGap) {
            Text("1")
                .font(.headline)
                .frame(width: 32, height: 32)
                .background(
                    Color.accentColor.opacity(0.16),
                    in: Circle()
                )
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: SettingsMetrics.compact) {
                Text("Calibrate tap acceptance")
                    .font(.headline)
                Text(
                    "Single taps establish your comfortable and firm impact range."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(totalSampleCount)/20")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}
