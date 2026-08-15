import MactivateRuntime
import SwiftUI

struct SettingsView: View {
    @ObservedObject var state: AppState
    let actions: SettingsActions

    @State private var showingActionLibrary = false

    var body: some View {
        ZStack {
            SettingsBackdrop()
            TabView {
                actionsPane
                    .tabItem { Label("Actions", systemImage: "bolt.fill") }
                GeneralSettingsPane(state: state, actions: actions)
                    .tabItem { Label("General", systemImage: "gearshape") }
                DiagnosticsPane(state: state)
                    .tabItem { Label("Diagnostics", systemImage: "waveform.path.ecg") }
            }
            .padding(SettingsMetrics.cardInset)
        }
        .frame(minWidth: 900, minHeight: 650)
        .tint(.accentColor)
        .sheet(isPresented: $showingActionLibrary) {
            ActionLibrarySheet(state: state, actions: actions)
        }
    }

    private var actionsPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsPageHeader(
                title: "Actions",
                subtitle: "Build actions once, then assign them to taps or the Notch Panel.",
                symbol: "bolt.fill",
                accessory: AnyView(
                    Button {
                        showingActionLibrary = true
                    } label: {
                        Label("Action Library", systemImage: "square.stack.3d.up")
                    }
                    .buttonStyle(.bordered)
                )
            )
            .padding(.horizontal, SettingsMetrics.pageInset)
            .padding(.top, SettingsMetrics.paneTopInset)
            .padding(.bottom, SettingsMetrics.sectionGap)

            ScrollView {
                VStack(alignment: .leading, spacing: SettingsMetrics.sectionGap) {
                    SettingsCard(
                        "Notch Panel",
                        subtitle: "Choose the four actions shown when the Notch Panel opens.",
                        symbol: "rectangle.topthird.inset.filled"
                    ) {
                        PanelSlotPreview(state: state, actions: actions)
                    }

                    SettingsCard(
                        "Palm rest gestures",
                        subtitle: state.spatialGesturesReady
                            ? "Each side and tap count can run a different action."
                            : "Complete both calibration steps to unlock assignments.",
                        symbol: "hand.tap.fill"
                    ) {
                        spatialGestureGrid
                        HStack(spacing: SettingsMetrics.controlGap) {
                            SettingsStatusBadge(
                                title: state.spatialGesturesReady
                                    ? "Ready" : "Setup required",
                                ready: state.spatialGesturesReady
                            )
                            Text(state.tapRegionCalibrationStatus)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Toggle(
                                "Palm rest actions",
                                isOn: Binding(
                                    get: {
                                        state.configuration
                                            .spatialTapDispatchEnabled
                                    },
                                    set: actions.setSpatialTapDispatchEnabled
                                )
                            )
                            .font(.caption.weight(.regular))
                            .foregroundStyle(.secondary)
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            .accessibilityIdentifier(
                                "spatial-tap-dispatch-toggle"
                            )
                        }
                    }

                    CalibrationWorkspace(state: state, actions: actions)
                }
                .padding(.horizontal, SettingsMetrics.pageInset)
                .padding(.bottom, SettingsMetrics.pageInset)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var spatialGestureGrid: some View {
        Grid(
            alignment: .leading,
            horizontalSpacing: SettingsMetrics.fieldGap,
            verticalSpacing: SettingsMetrics.controlGap
        ) {
            GridRow {
                Text("")
                Text("Double tap")
                    .font(.caption.weight(.semibold))
                Text("Triple tap")
                    .font(.caption.weight(.semibold))
            }
            GridRow {
                Label("Left palm rest", systemImage: "hand.point.left.fill")
                    .frame(width: 144, alignment: .leading)
                spatialGesturePicker(.leftDouble)
                spatialGesturePicker(.leftTriple)
            }
            GridRow {
                Label("Right palm rest", systemImage: "hand.point.right.fill")
                    .frame(width: 144, alignment: .leading)
                spatialGesturePicker(.rightDouble)
                spatialGesturePicker(.rightTriple)
            }
        }
    }

    private func spatialGesturePicker(
        _ gesture: PalmTapGesture
    ) -> some View {
        ActionPicker(
            selection: Binding(
                get: { state.configuration.spatialTapBindings[gesture] },
                set: { actions.setSpatialTapBinding($0, gesture) }
            ),
            actions: state.actions,
            includeShowPanel: true
        )
        .disabled(!state.spatialGesturesReady)
        .accessibilityLabel(
            "\(gesture.side.rawValue.capitalized) palm rest, " +
                "\(gesture.pattern.rawValue) tap action"
        )
        .accessibilityIdentifier(
            "spatial-\(gesture.side.rawValue)-" +
                "\(gesture.pattern.rawValue)-action"
        )
    }
}

private struct PanelSlotPreview: View {
    @ObservedObject var state: AppState
    let actions: SettingsActions

    private let labels = [
        "Top left", "Top right", "Bottom left", "Bottom right"
    ]

    var body: some View {
        Grid(
            horizontalSpacing: SettingsMetrics.fieldGap,
            verticalSpacing: SettingsMetrics.fieldGap
        ) {
            GridRow {
                slot(0)
                slot(1)
            }
            GridRow {
                slot(2)
                slot(3)
            }
        }
        .padding(SettingsMetrics.cardInset)
        .background(
            Color.black,
            in: UnevenRoundedRectangle(
                cornerRadii: .init(
                    topLeading: 6,
                    bottomLeading: 24,
                    bottomTrailing: 24,
                    topTrailing: 6
                )
            )
        )
        .overlay {
            UnevenRoundedRectangle(
                cornerRadii: .init(
                    topLeading: 6,
                    bottomLeading: 24,
                    bottomTrailing: 24,
                    topTrailing: 6
                )
            )
            .stroke(Color.white.opacity(0.10), lineWidth: 1)
        }
    }

    private func slot(_ index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(labels[index])
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.55))
                .textCase(.uppercase)
            ActionPicker(
                selection: Binding(
                    get: { state.preferences.normalizedQuickActionIDs[index] },
                    set: { actions.setQuickAction(index, $0) }
                ),
                actions: state.panelAssignableActions,
                includeShowPanel: false
            )
            .tint(.white)
        }
        .padding(SettingsMetrics.fieldGap)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .background(
            .white.opacity(0.10),
            in: RoundedRectangle(cornerRadius: SettingsMetrics.cardRadius)
        )
        .overlay {
            if state.settingsFocusedSlot == index {
                RoundedRectangle(cornerRadius: SettingsMetrics.cardRadius)
                    .stroke(Color.accentColor, lineWidth: 2)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(labels[index]) Notch Panel slot")
        .accessibilityIdentifier("panel-slot-\(index)")
    }
}
