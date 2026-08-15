import MactivateRuntime
import SwiftUI

struct CalibrationWorkspace: View {
    @ObservedObject var state: AppState
    let actions: SettingsActions
    @State private var isExpanded: Bool

    init(state: AppState, actions: SettingsActions) {
        self.state = state
        self.actions = actions
        _isExpanded = State(initialValue: !state.spatialGesturesReady)
    }

    var body: some View {
        SettingsCard(
            "Palm tap setup",
            subtitle: "Two user-paced steps make tap detection reliable.",
            symbol: "scope"
        ) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: SettingsMetrics.controlGap) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 16)
                    SettingsStatusBadge(
                        title: state.tapCalibrationProfile?.isValid == true
                            ? "Acceptance ready" : "Step 1 needed",
                        ready: state.tapCalibrationProfile?.isValid == true
                    )
                    SettingsStatusBadge(
                        title: state.tapRegionCalibrationProfile?.isValid == true
                            ? "Left/right ready" : "Step 2 needed",
                        ready: state.tapRegionCalibrationProfile?.isValid == true
                    )
                    Spacer()
                    Text(isExpanded ? "Hide setup" : "Show setup")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(minHeight: SettingsMetrics.rowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

            if isExpanded {
                VStack(
                    alignment: .leading,
                    spacing: SettingsMetrics.sectionGap
                ) {
                    TapAcceptanceCalibrationView(state: state, actions: actions)
                    Divider()
                    RegionCalibrationView(state: state, actions: actions)
                }
                .transition(.opacity)
            }
        }
    }
}
