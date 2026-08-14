import AppKit
import MactivateRuntime
import SwiftUI

struct SettingsActions {
    let setSpatialTapBinding: (ActionIdentifier?, PalmTapGesture) -> Void
    let setPanelHintsEnabled: (Bool) -> Void
    let setQuickAction: (Int, ActionIdentifier?) -> Void
    let addApplication: () -> Bool
    let addWebURL: (String, String) -> Bool
    let addShortcut: (String) -> Bool
    let deleteAction: (ActionIdentifier) -> Void
    let refreshShortcuts: () -> Void
    let setLaunchAtLogin: (Bool) -> Void
    let beginCalibrationCapture: (TapCalibrationTarget) -> Void
    let stopCalibrationCapture: () -> Void
    let saveCalibration: () -> Void
    let resetCalibration: () -> Void
    let beginRegionCalibration: () -> Void
    let stopRegionCalibration: () -> Void
    let saveRegionCalibration: () -> Void
    let resetRegionCalibration: () -> Void
    let testAction: (ActionIdentifier) -> Void
    let reset: () -> Void
}

private enum SettingsMetrics {
    static let hairline: CGFloat = 1
    static let compact: CGFloat = 4
    static let iconGap: CGFloat = 6
    static let controlGap: CGFloat = 8
    static let fieldGap: CGFloat = 12
    static let cardInset: CGFloat = 16
    static let headerGap: CGFloat = 18
    static let pageInset: CGFloat = 24
    static let sectionGap: CGFloat = 24
    static let majorGap: CGFloat = 32
    static let rowHeight: CGFloat = 48
    static let cardRadius: CGFloat = 12
}

private struct SettingsPageHeader: View {
    let title: String
    let subtitle: String
    let symbol: String
    var accessory: AnyView? = nil

    var body: some View {
        HStack(alignment: .center, spacing: SettingsMetrics.fieldGap) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(
                    Color.accentColor.gradient,
                    in: RoundedRectangle(cornerRadius: 8)
                )
            VStack(alignment: .leading, spacing: SettingsMetrics.compact) {
                Text(title)
                    .font(.title2.bold())
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: SettingsMetrics.fieldGap)
            accessory
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let symbol: String
    let content: Content

    init(
        _ title: String,
        subtitle: String? = nil,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.cardInset) {
            HStack(alignment: .top, spacing: SettingsMetrics.controlGap) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 24, height: 24)
                    .background(
                        Color.accentColor.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                VStack(alignment: .leading, spacing: SettingsMetrics.compact) {
                    Text(title)
                        .font(.headline)
                    if let subtitle {
                        Text(subtitle)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            content
        }
        .padding(SettingsMetrics.cardInset)
        .background(
            Color(nsColor: .controlBackgroundColor).opacity(0.78),
            in: RoundedRectangle(cornerRadius: SettingsMetrics.cardRadius)
        )
        .overlay {
            RoundedRectangle(cornerRadius: SettingsMetrics.cardRadius)
                .stroke(
                    Color(nsColor: .separatorColor).opacity(0.65),
                    lineWidth: SettingsMetrics.hairline
                )
        }
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let detail: String
    let symbol: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: SettingsMetrics.fieldGap) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: SettingsMetrics.compact) {
                Text(title)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: SettingsMetrics.fieldGap)
            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
        .frame(minHeight: SettingsMetrics.rowHeight)
    }
}

private struct SettingsStatusBadge: View {
    let title: String
    let ready: Bool

    var body: some View {
        Label(
            title,
            systemImage: ready
                ? "checkmark.circle.fill"
                : "exclamationmark.circle.fill"
        )
        .font(.caption.weight(.semibold))
        .foregroundStyle(ready ? Color.green : Color.orange)
        .padding(.horizontal, SettingsMetrics.controlGap)
        .padding(.vertical, SettingsMetrics.compact)
        .background(
            (ready ? Color.green : Color.orange).opacity(0.10),
            in: Capsule()
        )
    }
}

private struct SettingsBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.regularMaterial)
            LinearGradient(
                colors: [
                    Color.black.opacity(colorScheme == .dark ? 0.42 : 0.04),
                    Color(nsColor: .windowBackgroundColor).opacity(0.72)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }
}

struct SettingsView: View {
    @ObservedObject var state: AppState
    let actions: SettingsActions

    @State private var showingAddAction = false

    var body: some View {
        TabView {
            actionsPane
                .tabItem { Label("Actions", systemImage: "bolt.fill") }
            general
                .tabItem { Label("General", systemImage: "gearshape") }
            diagnostics
                .tabItem { Label("Diagnostics", systemImage: "waveform.path.ecg") }
        }
        .padding(SettingsMetrics.headerGap)
        .frame(minWidth: 900, minHeight: 650)
        .background(SettingsBackdrop())
        .tint(.accentColor)
        .sheet(isPresented: $showingAddAction) {
            AddActionSheet(
                state: state,
                actions: actions,
                isPresented: $showingAddAction
            )
        }
    }

    private var actionsPane: some View {
        HStack(alignment: .top, spacing: SettingsMetrics.pageInset) {
            ScrollView {
                VStack(alignment: .leading, spacing: SettingsMetrics.sectionGap) {
                    SettingsPageHeader(
                        title: "Actions",
                        subtitle: "Build actions once, then assign them to taps or the notch.",
                        symbol: "bolt.fill",
                        accessory: AnyView(
                            Button {
                                showingAddAction = true
                            } label: {
                                Label("New Action", systemImage: "plus")
                            }
                            .buttonStyle(.borderedProminent)
                        )
                    )

                    CalibrationWorkspace(state: state, actions: actions)

                    SettingsCard(
                        "Palm-rest gestures",
                        subtitle: state.spatialGesturesReady
                            ? "Each side and tap count can run a different action."
                            : "Complete both calibration steps to unlock assignments.",
                        symbol: "hand.tap.fill"
                    ) {
                        spatialGestureGrid
                        Divider()
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
                        }
                    }

                    SettingsCard(
                        "Notch panel",
                        subtitle: "Arrange the four actions shown in the expanded notch.",
                        symbol: "rectangle.topthird.inset.filled"
                    ) {
                        PanelSlotPreview(state: state, actions: actions)
                    }
                }
                .padding(.trailing, SettingsMetrics.compact)
                .padding(.bottom, SettingsMetrics.pageInset)
            }
            .frame(maxWidth: .infinity)

            Divider()

            actionLibrary
                .frame(width: 288)
        }
    }

    private var actionLibrary: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.fieldGap) {
            HStack {
                VStack(alignment: .leading, spacing: SettingsMetrics.compact) {
                    Text("Action Library")
                        .font(.headline)
                    Text("\(state.actions.count) available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    showingAddAction = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.bordered)
                .help("Create a new action")
            }

            Text("Test an action before assigning it to a gesture or slot.")
                .font(.callout)
                .foregroundStyle(.secondary)

            ScrollView {
                LazyVStack(spacing: SettingsMetrics.controlGap) {
                    ForEach(state.actions) { action in
                        HStack(spacing: SettingsMetrics.controlGap) {
                            Image(systemName: action.kind.symbolName)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 32, height: 32)
                                .background(
                                    Color.accentColor.opacity(0.10),
                                    in: RoundedRectangle(cornerRadius: 8)
                                )
                            VStack(
                                alignment: .leading,
                                spacing: SettingsMetrics.compact
                            ) {
                                Text(action.name)
                                    .font(.callout.weight(.medium))
                                    .lineLimit(1)
                                Text(actionDetail(action))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button {
                                actions.testAction(action.id)
                            } label: {
                                Image(systemName: "play.fill")
                            }
                            .buttonStyle(.borderless)
                            .help("Test \(action.name)")
                            if action.id != AppActionDefinition.showPanel.id {
                                Button(role: .destructive) {
                                    actions.deleteAction(action.id)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .help("Delete \(action.name)")
                            }
                        }
                        .padding(SettingsMetrics.controlGap)
                        .frame(minHeight: SettingsMetrics.rowHeight)
                        .background(
                            Color.black.opacity(0.16),
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(
                                    Color(nsColor: .separatorColor).opacity(0.45),
                                    lineWidth: SettingsMetrics.hairline
                                )
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier(
                            "action-library-\(action.id.rawValue)"
                        )
                    }
                }
            }

            if let error = state.actionError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(SettingsMetrics.cardInset)
        .background(
            Color(nsColor: .controlBackgroundColor).opacity(0.78),
            in: RoundedRectangle(cornerRadius: SettingsMetrics.cardRadius)
        )
        .overlay {
            RoundedRectangle(cornerRadius: SettingsMetrics.cardRadius)
                .stroke(
                    Color(nsColor: .separatorColor).opacity(0.65),
                    lineWidth: SettingsMetrics.hairline
                )
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

    private var general: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsMetrics.sectionGap) {
                SettingsPageHeader(
                    title: "General",
                    subtitle: "Startup, panel behavior, and calibration maintenance.",
                    symbol: "gearshape.fill"
                )

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
                    "Experimental hover",
                    subtitle: "A best-effort hint that can reveal the notch panel.",
                    symbol: "light.max"
                ) {
                    SettingsToggleRow(
                        title: "Open from ambient-light hints",
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
                            "Hover hints never run an action."
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
                    Divider()
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
                    subtitle: "Clears custom actions, notch slots, gesture assignments, and hover preferences. Calibration is preserved.",
                    symbol: "arrow.counterclockwise"
                ) {
                    Button(
                        "Reset Actions & Assignments",
                        role: .destructive,
                        action: actions.reset
                    )
                }
            }
            .padding(.trailing, SettingsMetrics.compact)
            .padding(.bottom, SettingsMetrics.pageInset)
        }
    }

    private var diagnostics: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.cardInset) {
            SettingsPageHeader(
                title: "Diagnostics",
                subtitle: "Live sensor readiness and the latest tap decision.",
                symbol: "waveform.path.ecg",
                accessory: AnyView(
                    Button {
                        copyDiagnostics()
                    } label: {
                        Label("Copy Report", systemImage: "doc.on.doc")
                    }
                )
            )
            HStack(spacing: SettingsMetrics.fieldGap) {
                statusCard(
                    title: "Palm sensor",
                    value: state.tapStatus,
                    symbol: "hand.tap",
                    ready: tapSensorReady
                )
                statusCard(
                    title: "Tap acceptance",
                    value: state.tapCalibrationStatus,
                    symbol: "scope",
                    ready: state.tapCalibrationProfile?.isValid == true
                )
                statusCard(
                    title: "Left/right",
                    value: state.tapRegionStatus,
                    symbol: "arrow.left.and.right",
                    ready: state.spatialGesturesReady
                )
            }
            if let feedback = state.lastTapFeedback {
                SettingsCard(
                    "Latest tap decision",
                    subtitle: "Updates after every detected impact group.",
                    symbol: "waveform"
                ) {
                    VStack(
                        alignment: .leading,
                        spacing: SettingsMetrics.controlGap
                    ) {
                        Text(state.tapFeedbackDescription)
                            .font(.headline)
                        Text("Peak \(feedback.features.peakG, format: .number.precision(.fractionLength(3))) g · \(feedback.memberCount) candidate\(feedback.memberCount == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(state.tapRegionFeedbackDescription)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        if case .rejected(let reason) = feedback.outcome {
                            Label(reason.guidance, systemImage: "lightbulb")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            ScrollView {
                Text(state.diagnosticText)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(SettingsMetrics.cardInset)
            }
            .background(
                Color.black.opacity(0.48),
                in: RoundedRectangle(cornerRadius: SettingsMetrics.cardRadius)
            )
            .overlay {
                RoundedRectangle(cornerRadius: SettingsMetrics.cardRadius)
                    .stroke(
                        Color.white.opacity(0.08),
                        lineWidth: SettingsMetrics.hairline
                    )
            }
            HStack {
                Button("Copy Diagnostics", action: copyDiagnostics)
                Spacer()
                if let warning = state.recentWarning {
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
            }
        }
        .padding(.bottom, SettingsMetrics.controlGap)
    }

    private func statusCard(
        title: String,
        value: String,
        symbol: String,
        ready: Bool
    ) -> some View {
        HStack(spacing: SettingsMetrics.controlGap) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(ready ? Color.green : Color.orange)
                .frame(width: 32, height: 32)
                .background(
                    (ready ? Color.green : Color.orange).opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 8)
                )
            VStack(
                alignment: .leading,
                spacing: SettingsMetrics.compact
            ) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.callout.weight(.semibold))
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(SettingsMetrics.fieldGap)
        .frame(maxWidth: .infinity)
        .background(
            Color(nsColor: .controlBackgroundColor).opacity(0.78),
            in: RoundedRectangle(cornerRadius: SettingsMetrics.cardRadius)
        )
        .overlay {
            RoundedRectangle(cornerRadius: SettingsMetrics.cardRadius)
                .stroke(
                    Color(nsColor: .separatorColor).opacity(0.65),
                    lineWidth: SettingsMetrics.hairline
                )
        }
        .accessibilityElement(children: .combine)
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
                    : "circle.dashed"
            )
            .foregroundStyle(ready ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: SettingsMetrics.compact) {
                Text(title)
                Text(value)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(minHeight: 36)
        .accessibilityElement(children: .combine)
    }

    private func copyDiagnostics() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(
            state.diagnosticText,
            forType: .string
        )
    }

    private var tapSensorReady: Bool {
        if case .available = state.snapshot.tap {
            return true
        }
        return false
    }

    private func actionDetail(_ action: AppActionDefinition) -> String {
        switch action.kind {
        case .showPanel: return "Built in"
        case .application(let identifier): return identifier
        case .webURL(let value): return value
        case .shortcut: return "Shortcut"
        }
    }
}

private struct ActionPicker: View {
    @Binding var selection: ActionIdentifier?
    let actions: [AppActionDefinition]
    let includeShowPanel: Bool

    var body: some View {
        Picker("", selection: $selection) {
            Text("None").tag(ActionIdentifier?.none)
            ForEach(filteredActions) { action in
                Label(action.name, systemImage: action.kind.symbolName)
                    .tag(Optional(action.id))
            }
            if let selection,
               !filteredActions.contains(where: { $0.id == selection }) {
                Text("Missing action").tag(Optional(selection))
            }
        }
        .labelsHidden()
    }

    private var filteredActions: [AppActionDefinition] {
        actions.filter {
            includeShowPanel || $0.id != AppActionDefinition.showPanel.id
        }
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
            RoundedRectangle(cornerRadius: SettingsMetrics.cardRadius)
                .stroke(
                    state.settingsFocusedSlot == index
                        ? Color.accentColor : Color.white.opacity(0.08),
                    lineWidth: 2
                )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(labels[index]) notch slot")
        .accessibilityIdentifier("panel-slot-\(index)")
    }
}

private struct CalibrationWorkspace: View {
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
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(
                    alignment: .leading,
                    spacing: SettingsMetrics.sectionGap
                ) {
                    CalibrationView(state: state, actions: actions)
                    Divider()
                    RegionCalibrationView(state: state, actions: actions)
                }
                .padding(.top, SettingsMetrics.cardInset)
            } label: {
                HStack(spacing: SettingsMetrics.controlGap) {
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
            }
        }
    }
}

private struct CalibrationView: View {
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

            VStack(spacing: SettingsMetrics.controlGap) {
                ForEach(targets, id: \.self) { target in
                    captureRow(target)
                }
            }

            if let feedback = state.lastTapFeedback,
               feedback.outcome == .candidate {
                Label(
                    "Impact detected — resolving the tap count.",
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
        }
    }

    private func captureRow(_ target: TapCalibrationTarget) -> some View {
        let count = state.tapCalibrationDraft.sampleCount(
            side: target.side,
            intensity: target.intensity
        )
        let isActive = state.tapCalibrationTarget == target
        return HStack(spacing: SettingsMetrics.controlGap) {
            Image(
                systemName: count >= TapCalibrationDraft.requiredSamplesPerTarget
                    ? "checkmark.circle.fill" : "circle"
            )
            .foregroundStyle(
                count >= TapCalibrationDraft.requiredSamplesPerTarget
                    ? .green : .secondary
            )
            Text("\(target.side.rawValue.capitalized) · \(target.intensity.rawValue.capitalized)")
            Spacer()
            Text(
                "\(count)/\(TapCalibrationDraft.requiredSamplesPerTarget)"
            )
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Button(
                isActive ? "Capturing…" :
                    count >= TapCalibrationDraft.requiredSamplesPerTarget
                        ? "Redo" : "Capture"
            ) {
                actions.beginCalibrationCapture(target)
            }
            .disabled(isActive)
        }
        .padding(.horizontal, SettingsMetrics.controlGap)
        .frame(minHeight: SettingsMetrics.rowHeight)
        .background(
            isActive
                ? Color.accentColor.opacity(0.10)
                : Color.black.opacity(0.12),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    isActive
                        ? Color.accentColor.opacity(0.65)
                        : Color(nsColor: .separatorColor).opacity(0.35),
                    lineWidth: SettingsMetrics.hairline
                )
        }
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

private struct RegionCalibrationView: View {
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
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(
                        Color.accentColor.opacity(0.32),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                    VStack(
                        alignment: .leading,
                        spacing: SettingsMetrics.compact
                    ) {
                        Text(
                            "\(target.side.rawValue.capitalized) palm rest"
                        )
                        .font(.title3.bold())
                        Text(
                            "\(target.pattern.rawValue.capitalized) tap · " +
                                "perform \(target.pattern.memberCount) taps"
                        )
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.68))
                    }
                    Spacer()
                    Text("READY")
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                }
                .padding(SettingsMetrics.cardInset)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Color.black.opacity(0.72),
                    in: RoundedRectangle(
                        cornerRadius: SettingsMetrics.cardRadius
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: SettingsMetrics.cardRadius
                    )
                    .stroke(
                        Color.accentColor.opacity(0.36),
                        lineWidth: SettingsMetrics.hairline
                    )
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("region-calibration-target")
            }

            VStack(spacing: SettingsMetrics.controlGap) {
                ForEach(
                    TapRegionCalibrationTarget.ordered,
                    id: \.self
                ) { target in
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
                Button(
                    "Save Step 2",
                    action: actions.saveRegionCalibration
                )
                .disabled(
                    !state.tapRegionCalibrationDraft.isComplete ||
                        state.tapRegionCalibrationTarget != nil
                )
            }
        }
    }

    private func calibrationProgressRow(
        _ target: TapRegionCalibrationTarget
    ) -> some View {
        let count = state.tapRegionCalibrationDraft.sampleCount(target: target)
        let required = TapRegionCalibrationDraft.requiredGesturesPerTarget
        return HStack(spacing: SettingsMetrics.controlGap) {
            Image(
                systemName: count >= required
                    ? "checkmark.circle.fill" : "circle"
            )
            .foregroundStyle(count >= required ? Color.green : Color.secondary)
            Text("\(target.side.rawValue.capitalized) palm rest")
            Text("·")
                .foregroundStyle(.tertiary)
            Text("\(target.pattern.rawValue.capitalized) tap")
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(count)/\(required)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, SettingsMetrics.controlGap)
        .frame(minHeight: 36)
        .background(
            Color.black.opacity(0.12),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(target.side.rawValue) \(target.pattern.rawValue), " +
                "\(count) of \(required)"
        )
    }
}

private struct AddActionSheet: View {
    @ObservedObject var state: AppState
    let actions: SettingsActions
    @Binding var isPresented: Bool

    @State private var selection = 0
    @State private var webName = ""
    @State private var webAddress = "https://"
    @State private var shortcutName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.cardInset) {
            HStack(spacing: SettingsMetrics.fieldGap) {
                Image(systemName: "plus.square.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Color.accentColor)
                VStack(
                    alignment: .leading,
                    spacing: SettingsMetrics.compact
                ) {
                    Text("New Action")
                        .font(.title2.bold())
                    Text("Choose one focused response for a tap or notch slot.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Picker("Action type", selection: $selection) {
                Text("Application").tag(0)
                Text("Web Link").tag(1)
                Text("Shortcut").tag(2)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Action type")

            Group {
                switch selection {
                case 0:
                    actionTypeCard(
                        symbol: "app.dashed",
                        title: "Launch an application",
                        detail: "Choose any installed macOS application."
                    ) {
                        Button("Choose Application…") {
                            if actions.addApplication() {
                                isPresented = false
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                case 1:
                    actionTypeCard(
                        symbol: "link",
                        title: "Open a web link",
                        detail: "Only HTTP and HTTPS addresses are accepted."
                    ) {
                        VStack(
                            alignment: .leading,
                            spacing: SettingsMetrics.fieldGap
                        ) {
                            labeledField("Name") {
                                TextField("Documentation", text: $webName)
                            }
                            labeledField("Address") {
                                TextField(
                                    "https://example.com",
                                    text: $webAddress
                                )
                            }
                            HStack {
                                Spacer()
                                Button("Add Web Link") {
                                    if actions.addWebURL(
                                        webName,
                                        webAddress
                                    ) {
                                        isPresented = false
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(
                                    webName.trimmingCharacters(
                                        in: .whitespaces
                                    ).isEmpty
                                )
                            }
                        }
                    }
                default:
                    actionTypeCard(
                        symbol: "command",
                        title: "Run a macOS Shortcut",
                        detail: "Choose from the Shortcuts available on this Mac."
                    ) {
                        Picker("Shortcut", selection: $shortcutName) {
                            Text("Choose a Shortcut").tag("")
                            ForEach(state.availableShortcuts, id: \.self) {
                                Text($0).tag($0)
                            }
                        }
                        HStack {
                            Button {
                                actions.refreshShortcuts()
                            } label: {
                                Label("Refresh", systemImage: "arrow.clockwise")
                            }
                            Button("Add Shortcut") {
                                if actions.addShortcut(shortcutName) {
                                    isPresented = false
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(
                                shortcutName.trimmingCharacters(in: .whitespaces).isEmpty
                            )
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)

            if let error = state.actionError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
            }
        }
        .padding(SettingsMetrics.pageInset)
        .frame(width: 576, height: 384)
        .background(SettingsBackdrop())
        .onAppear(perform: actions.refreshShortcuts)
    }

    private func actionTypeCard<Content: View>(
        symbol: String,
        title: String,
        detail: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.cardInset) {
            HStack(spacing: SettingsMetrics.fieldGap) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 36, height: 36)
                    .background(
                        Color.accentColor.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                VStack(
                    alignment: .leading,
                    spacing: SettingsMetrics.compact
                ) {
                    Text(title)
                        .font(.headline)
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            content()
        }
        .padding(SettingsMetrics.cardInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.black.opacity(0.22),
            in: RoundedRectangle(cornerRadius: SettingsMetrics.cardRadius)
        )
        .overlay {
            RoundedRectangle(cornerRadius: SettingsMetrics.cardRadius)
                .stroke(
                    Color(nsColor: .separatorColor).opacity(0.55),
                    lineWidth: SettingsMetrics.hairline
                )
        }
    }

    private func labeledField<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.iconGap) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }
}

@MainActor
final class SettingsWindowController: NSWindowController {
    init(state: AppState, actions: SettingsActions) {
        let hostingController = NSHostingController(
            rootView: SettingsView(state: state, actions: actions)
        )
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Mactivate Settings"
        window.styleMask = [
            .titled,
            .closable,
            .resizable,
            .fullSizeContentView
        ]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .visible
        window.backgroundColor = .windowBackgroundColor
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 900, height: 650)
        window.setContentSize(NSSize(width: 960, height: 720))
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

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
                Color(nsColor: .controlBackgroundColor).opacity(0.78),
                in: RoundedRectangle(cornerRadius: SettingsMetrics.cardRadius)
            )
            .overlay {
                RoundedRectangle(cornerRadius: SettingsMetrics.cardRadius)
                    .stroke(
                        Color(nsColor: .separatorColor).opacity(0.65),
                        lineWidth: SettingsMetrics.hairline
                    )
            }

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
        .foregroundStyle(complete ? Color.green : Color.primary)
        .frame(minHeight: 36)
    }
}

@MainActor
final class OnboardingWindowController: NSWindowController {
    init(
        state: AppState,
        openSettings: @escaping () -> Void,
        complete: @escaping () -> Void
    ) {
        let hostingController = NSHostingController(
            rootView: OnboardingView(
                state: state,
                openSettings: openSettings,
                complete: complete
            )
        )
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Welcome to Mactivate"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
