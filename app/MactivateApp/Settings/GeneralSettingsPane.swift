import SwiftUI

struct GeneralSettingsPane: View {
    @ObservedObject var state: AppState
    let actions: SettingsActions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsPageHeader(
                title: "General",
                subtitle: "Startup, Notch Hover, and calibration maintenance.",
                symbol: "gearshape.fill"
            )
            .padding(.horizontal, SettingsMetrics.pageInset)
            .padding(.top, SettingsMetrics.paneTopInset)
            .padding(.bottom, SettingsMetrics.sectionGap)

            ScrollView {
                VStack(alignment: .leading, spacing: SettingsMetrics.sectionGap) {
                SettingsCard(
                    "Startup",
                    subtitle: "Keep Mactivate available from the menu bar.",
                    symbol: "power"
                ) {
                    SettingsToggleRow(
                        title: "Launch at login",
                        detail: state.launchAtLoginStatus.title,
                        symbol: "arrow.clockwise",
                        isOn: Binding(
                            get: {
                                state.launchAtLoginStatus.isRegistered
                            },
                            set: actions.setLaunchAtLogin
                        )
                    )
                }

                SettingsCard(
                    "Notch Hover",
                    subtitle: "A best-effort hint that can open the Notch Panel.",
                    symbol: "light.max"
                ) {
                    SettingsToggleRow(
                        title: "Open the Notch Panel from ambient-light hints",
                        detail: state.panelHintStatus,
                        symbol: "hand.wave",
                        isOn: Binding(
                            get: {
                                state.configuration.panelHintsEnabled
                            },
                            set: actions.setPanelHintsEnabled
                        )
                    )
                    Text(
                        "Lighting and moving shadows can make this unavailable. " +
                            "Notch Hover never runs an action."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                SettingsCard(
                    "Calibration",
                    subtitle: "Review readiness or reset one calibration independently.",
                    symbol: "scope"
                ) {
                    calibrationStatusRow(
                        title: "Tap acceptance",
                        value: state.tapCalibrationStatus,
                        ready: state.tapCalibrationProfile?.isValid == true
                    )
                    calibrationStatusRow(
                        title: "Left/right detection",
                        value: state.tapRegionCalibrationStatus,
                        ready: state.tapRegionCalibrationProfile?.isValid == true
                    )
                    HStack(spacing: SettingsMetrics.controlGap) {
                        Button(
                            "Reset tap acceptance",
                            role: .destructive,
                            action: actions.resetCalibration
                        )
                        .disabled(
                            state.tapCalibrationProfile == nil &&
                                state.tapCalibrationStoreWarning == nil
                        )
                        Button(
                            "Reset left/right",
                            role: .destructive,
                            action: actions.resetRegionCalibration
                        )
                        .disabled(
                            state.tapRegionCalibrationProfile == nil &&
                                state.tapRegionCalibrationStoreWarning == nil
                        )
                    }
                }

                SettingsCard(
                    "Reset actions and assignments",
                    subtitle: "Clears custom actions, Notch Panel slots, gesture assignments, and Notch Hover preferences. Calibration is preserved.",
                    symbol: "arrow.counterclockwise"
                ) {
                    Button(
                        "Reset Actions & Assignments",
                        role: .destructive,
                        action: actions.reset
                    )
                }
            }
                .padding(.horizontal, SettingsMetrics.pageInset)
                .padding(.bottom, SettingsMetrics.pageInset)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func calibrationStatusRow(
        title: String,
        value: String,
        ready: Bool
    ) -> some View {
        HStack(spacing: SettingsMetrics.fieldGap) {
            Image(
                systemName: ready
                    ? "checkmark.circle.fill"
                    : "exclamationmark.circle.fill"
            )
            .foregroundStyle(ready ? Color.secondary : Color.orange)
            VStack(alignment: .leading, spacing: SettingsMetrics.compact) {
                Text(title)
                Text(value)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(minHeight: SettingsMetrics.rowHeight)
        .accessibilityElement(children: .combine)
    }
}
