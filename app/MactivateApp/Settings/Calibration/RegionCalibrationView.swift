import MactivateRuntime
import SwiftUI

struct RegionCalibrationView: View {
    @ObservedObject var state: AppState
    let actions: SettingsActions

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.cardInset) {
            HStack(spacing: SettingsMetrics.fieldGap) {
                Text("2")
                    .font(.headline)
                    .frame(width: 32, height: 32)
                    .background(
                        Color.accentColor.opacity(0.16),
                        in: Circle()
                    )
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: SettingsMetrics.compact) {
                    Text("Calibrate left/right detection")
                        .font(.headline)
                    Text(
                        "Guided double and triple taps teach the spatial model."
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(state.tapRegionCalibrationDraft.totalSampleCount)/20")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(
                value: Double(
                    state.tapRegionCalibrationDraft.totalSampleCount
                ),
                total: 20
            )
            .accessibilityLabel("Left and right calibration progress")

            Text(
                "One target stays onscreen until a valid gesture is detected. " +
                    "There is no countdown or time limit."
            )
            .font(.callout)
            .foregroundStyle(.secondary)

            if let target = state.tapRegionCalibrationTarget {
                HStack(spacing: SettingsMetrics.fieldGap) {
                    Image(
                        systemName: target.side == .left
                            ? "hand.point.left.fill"
                            : "hand.point.right.fill"
                    )
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    VStack(
                        alignment: .leading,
                        spacing: SettingsMetrics.compact
                    ) {
                        Text(
                            "\(target.side.rawValue.capitalized) palm rest"
                        )
                        .font(.title3.bold())
                        Text(
                            "\(target.pattern.rawValue.capitalized) tap " +
                                "(\(target.pattern.memberCount) taps)"
                        )
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("READY")
                        .font(.caption.bold())
                        .foregroundStyle(Color.accentColor)
                }
                .padding(SettingsMetrics.cardInset)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Color.accentColor.opacity(0.12),
                    in: RoundedRectangle(
                        cornerRadius: SettingsMetrics.cardRadius
                    )
                )
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("region-calibration-target")
            }

            VStack(spacing: SettingsMetrics.iconGap) {
                ForEach(TapRegionCalibrationTarget.ordered, id: \.self) { target in
                    calibrationProgressRow(target)
                }
            }

            if let error = state.tapRegionCalibrationError {
                Label(error, systemImage: "arrow.clockwise.circle")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            HStack {
                if state.tapRegionCalibrationTarget == nil {
                    Button(
                        state.tapRegionCalibrationDraft.totalSampleCount == 0
                            ? "Start Step 2"
                            : "Restart Step 2",
                        action: actions.beginRegionCalibration
                    )
                    .buttonStyle(.borderedProminent)
                    .disabled(!state.canCalibrateTapRegion)
                } else {
                    Button(
                        "Pause calibration",
                        action: actions.stopRegionCalibration
                    )
                }
                Spacer()
                if state.tapRegionCalibrationError != nil,
                   state.tapRegionCalibrationDraft.isComplete,
                   state.tapRegionCalibrationTarget == nil {
                    Button(
                        "Retry Save",
                        action: actions.saveRegionCalibration
                    )
                }
            }
            .padding(.horizontal, SettingsMetrics.fieldGap)
        }
    }

    private func calibrationProgressRow(
        _ target: TapRegionCalibrationTarget
    ) -> some View {
        let count = state.tapRegionCalibrationDraft.sampleCount(target: target)
        let required = TapRegionCalibrationDraft.requiredGesturesPerTarget
        let isDone = count >= required
        return HStack(spacing: SettingsMetrics.controlGap) {
            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isDone ? .primary : .secondary)
            Text("\(target.side.rawValue.capitalized) palm rest")
            Text("\(target.pattern.rawValue.capitalized) tap")
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(count)/\(required)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, SettingsMetrics.fieldGap)
        .frame(minHeight: SettingsMetrics.rowHeight)
        .background(
            Color(nsColor: .textBackgroundColor),
            in: RoundedRectangle(cornerRadius: 6)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(target.side.rawValue) \(target.pattern.rawValue), " +
                "\(count) of \(required)"
        )
    }
}
