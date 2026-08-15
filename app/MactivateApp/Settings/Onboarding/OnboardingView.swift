import SwiftUI

struct OnboardingView: View {
    @ObservedObject var state: AppState
    let openSettings: () -> Void
    let complete: () -> Void

    var body: some View {
        VStack(spacing: SettingsMetrics.sectionGap) {
            Image(systemName: "hand.tap.fill")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .background(
                    Color.black,
                    in: UnevenRoundedRectangle(
                        cornerRadii: .init(
                            topLeading: 8,
                            bottomLeading: 24,
                            bottomTrailing: 24,
                            topTrailing: 8
                        )
                    )
                )

            Text("Set up Mactivate")
                .font(.title.bold())
            Text(
                "A user-paced setup makes palm taps reliable and verifies " +
                    "each action before you rely on it."
            )
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: SettingsMetrics.fieldGap) {
                setupStep(
                    "Calibrate tap acceptance",
                    complete: state.tapCalibrationProfile?.isValid == true
                )
                setupStep(
                    "Calibrate left/right double and triple taps",
                    complete: state.tapRegionCalibrationProfile?.isValid == true
                )
                setupStep(
                    "Add and test your first action",
                    complete: !state.preferences.actions.isEmpty
                )
                setupStep(
                    "Assign one of the four spatial gestures",
                    complete: !state.configuration.spatialTapBindings.isEmpty
                )
                setupStep(
                    "Optionally fill the four notch slots",
                    complete: state.preferences.normalizedQuickActionIDs.contains {
                        $0 != nil
                    }
                )
            }
            .padding(SettingsMetrics.cardInset)
            .frame(maxWidth: 432, alignment: .leading)
            .background(
                Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: SettingsMetrics.cardRadius)
            )

            HStack(spacing: SettingsMetrics.controlGap) {
                Button("Set Up Now") {
                    openSettings()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                Button("Finish Later", action: complete)
            }
        }
        .padding(SettingsMetrics.majorGap)
        .frame(width: 576, height: 480)
        .background(SettingsBackdrop())
    }

    private func setupStep(_ title: String, complete: Bool) -> some View {
        Label(
            title,
            systemImage: complete ? "checkmark.circle.fill" : "circle"
        )
        .foregroundStyle(complete ? Color.primary : Color.secondary)
        .frame(minHeight: SettingsMetrics.rowHeight)
    }
}
