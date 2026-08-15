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
    static let controlGap: CGFloat = 10
    static let fieldGap: CGFloat = 14
    static let cardInset: CGFloat = 20
    static let headerToCard: CGFloat = 12
    static let pageInset: CGFloat = 28
    static let paneTopInset: CGFloat = 18
    static let sectionGap: CGFloat = 30
    static let majorGap: CGFloat = 32
    static let rowHeight: CGFloat = 44
    static let cardRadius: CGFloat = 10
}

private struct SettingsPageHeader: View {
    let title: String
    let subtitle: String
    let symbol: String
    var accessory: AnyView? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: SettingsMetrics.fieldGap) {
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

/// A native-style grouped section. Mirrors the look of a macOS System
/// Settings pane: a plain header above a single flat surface, rather than
/// a separately bordered "card" per section.
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
        VStack(alignment: .leading, spacing: SettingsMetrics.headerToCard) {
            VStack(alignment: .leading, spacing: SettingsMetrics.compact) {
                Text(title)
                    .font(.headline)
                if let subtitle {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: SettingsMetrics.cardInset) {
                content
            }
            .padding(SettingsMetrics.cardInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: SettingsMetrics.cardRadius)
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
        .foregroundStyle(ready ? Color.secondary : Color.orange)
        .padding(.horizontal, SettingsMetrics.controlGap)
        .padding(.vertical, SettingsMetrics.compact)
        .background(
            ready
                ? Color.secondary.opacity(0.12)
                : Color.orange.opacity(0.12),
            in: Capsule()
        )
    }
}

private struct SettingsBackdrop: View {
    var body: some View {
        Color(nsColor: .windowBackgroundColor)
            .ignoresSafeArea()
    }
}

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
                general
                    .tabItem { Label("General", systemImage: "gearshape") }
                diagnostics
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
                subtitle: "Build actions once, then assign them to taps or the notch.",
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
                        "Notch panel",
                        subtitle: "Arrange the four actions shown in the expanded notch.",
                        symbol: "rectangle.topthird.inset.filled"
                    ) {
                        PanelSlotPreview(state: state, actions: actions)
                    }

                    SettingsCard(
                        "Palm-rest gestures",
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

    private var general: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsPageHeader(
                title: "General",
                subtitle: "Startup, panel behavior, and calibration maintenance.",
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
                .padding(.horizontal, SettingsMetrics.pageInset)
                .padding(.bottom, SettingsMetrics.pageInset)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var diagnostics: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.cardInset) {
            SettingsPageHeader(
                title: "Diagnostics",
                subtitle: "Review the latest tap decision and runtime report.",
                symbol: "waveform.path.ecg"
            )
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
                        Text(state.tapFeedbackSummary)
                            .font(.headline)
                        if case .rejected = feedback.outcome {
                            Label(
                                state.tapFeedbackSummaryDetail,
                                systemImage: "lightbulb"
                            )
                            .font(.callout)
                            .foregroundStyle(.orange)
                        } else {
                            Text(state.tapFeedbackSummaryDetail)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        HStack(spacing: SettingsMetrics.fieldGap) {
                            Text("Peak \(feedback.features.peakG, format: .number.precision(.fractionLength(3))) g")
                            Text("\(feedback.memberCount) detected impact\(feedback.memberCount == 1 ? "" : "s")")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
            .scrollIndicators(.hidden)
            .background(
                Color(nsColor: .textBackgroundColor),
                in: RoundedRectangle(cornerRadius: SettingsMetrics.cardRadius)
            )
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
        .padding(.horizontal, SettingsMetrics.pageInset)
        .padding(.top, SettingsMetrics.paneTopInset)
        .padding(.bottom, SettingsMetrics.pageInset)
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

    private func copyDiagnostics() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(
            state.diagnosticText,
            forType: .string
        )
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
            if state.settingsFocusedSlot == index {
                RoundedRectangle(cornerRadius: SettingsMetrics.cardRadius)
                    .stroke(Color.accentColor, lineWidth: 2)
            }
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
                    CalibrationView(state: state, actions: actions)
                    Divider()
                    RegionCalibrationView(state: state, actions: actions)
                }
                .transition(.opacity)
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

/// A standalone modal for browsing, testing, and deleting saved actions.
/// Kept separate from the Actions tab so assigning gestures/slots and
/// managing the underlying library are two distinct, focused surfaces.
private struct ActionLibrarySheet: View {
    @ObservedObject var state: AppState
    let actions: SettingsActions
    @Environment(\.dismiss) private var dismiss

    @State private var showingAddAction = false

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.cardInset) {
            HStack(alignment: .top, spacing: SettingsMetrics.fieldGap) {
                VStack(alignment: .leading, spacing: SettingsMetrics.compact) {
                    Text("Action Library")
                        .font(.title2.bold())
                    Text(
                        "\(state.actions.count) action" +
                            (state.actions.count == 1 ? "" : "s") +
                            " available. Test one before assigning it to a gesture or slot."
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: SettingsMetrics.fieldGap)
                Button {
                    showingAddAction = true
                } label: {
                    Label("New Action", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }

            ScrollView {
                LazyVStack(spacing: SettingsMetrics.iconGap) {
                    ForEach(state.actions) { action in
                        actionRow(action)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: .infinity)

            if let error = state.actionError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(SettingsMetrics.pageInset)
        .frame(width: 480, height: 560)
        .background(SettingsBackdrop())
        .sheet(isPresented: $showingAddAction) {
            AddActionSheet(
                state: state,
                actions: actions,
                isPresented: $showingAddAction
            )
        }
    }

    private func actionRow(_ action: AppActionDefinition) -> some View {
        HStack(spacing: SettingsMetrics.controlGap) {
            Image(systemName: action.kind.symbolName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: SettingsMetrics.compact) {
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
        .padding(.vertical, SettingsMetrics.controlGap)
        .frame(minHeight: SettingsMetrics.rowHeight)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("action-library-\(action.id.rawValue)")
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
            VStack(alignment: .leading, spacing: SettingsMetrics.compact) {
                Text("New Action")
                    .font(.title2.bold())
                Text("Choose one focused response for a tap or notch slot.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
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
            VStack(alignment: .leading, spacing: SettingsMetrics.compact) {
                Label(title, systemImage: symbol)
                    .font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
