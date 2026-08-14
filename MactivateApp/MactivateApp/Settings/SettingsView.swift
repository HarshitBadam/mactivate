import AppKit
import MactivateRuntime
import SwiftUI

struct SettingsActions {
    let setSpatialTapBinding: (ActionIdentifier?, PalmTapGesture) -> Void
    let setPanelHintsEnabled: (Bool) -> Void
    let setQuickAction: (Int, ActionIdentifier?) -> Void
    let addApplication: () -> Void
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
        .padding(18)
        .frame(minWidth: 780, minHeight: 620)
        .sheet(isPresented: $showingAddAction) {
            AddActionSheet(
                state: state,
                actions: actions,
                isPresented: $showingAddAction
            )
        }
    }

    private var actionsPane: some View {
        HStack(alignment: .top, spacing: 22) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Actions")
                            .font(.largeTitle.bold())
                        Text("Choose what appears in the notch and what each palm tap runs.")
                            .foregroundStyle(.secondary)
                    }

                    GroupBox("Notch panel") {
                        PanelSlotPreview(state: state, actions: actions)
                            .padding(.top, 4)
                    }

                    GroupBox("Palm-rest gestures") {
                        VStack(alignment: .leading, spacing: 12) {
                            spatialGestureGrid
                            Divider()
                            HStack {
                                Label(state.tapStatus, systemImage: "sensor.fill")
                                Spacer()
                                Text(state.tapRegionCalibrationStatus)
                                    .foregroundStyle(
                                        state.spatialGesturesReady ?
                                            Color.secondary : Color.orange
                                    )
                            }
                            .font(.caption)
                            if !state.spatialGesturesReady {
                                Button("Calibrate left/right detection") {
                                    actions.beginRegionCalibration()
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(!state.canCalibrateTapRegion)
                            }
                        }
                        .padding(.top, 4)
                    }

                    CalibrationView(state: state, actions: actions)
                    RegionCalibrationView(state: state, actions: actions)
                }
                .padding(.trailing, 4)
            }
            .frame(maxWidth: .infinity)

            Divider()

            actionLibrary
                .frame(width: 275)
        }
    }

    private var actionLibrary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Action library")
                    .font(.title2.bold())
                Spacer()
                Button {
                    showingAddAction = true
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }

            Text("Test an action here before assigning it.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(state.actions) { action in
                        HStack(spacing: 9) {
                            Image(systemName: action.kind.symbolName)
                                .frame(width: 24)
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(action.name)
                                    .lineLimit(1)
                                Text(actionDetail(action))
                                    .font(.caption2)
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
                        .padding(10)
                        .background(
                            .primary.opacity(0.055),
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                    }
                }
            }

            if let error = state.actionError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button {
                showingAddAction = true
            } label: {
                Label("Add an action", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var spatialGestureGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
            GridRow {
                Text("")
                Text("Double tap")
                    .font(.caption.weight(.semibold))
                Text("Triple tap")
                    .font(.caption.weight(.semibold))
            }
            GridRow {
                Label("Left palm rest", systemImage: "hand.point.left.fill")
                    .frame(width: 130, alignment: .leading)
                spatialGesturePicker(.leftDouble)
                spatialGesturePicker(.leftTriple)
            }
            GridRow {
                Label("Right palm rest", systemImage: "hand.point.right.fill")
                    .frame(width: 130, alignment: .leading)
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
        Form {
            Section("Startup") {
                Toggle(
                    "Launch Mactivate at login",
                    isOn: Binding(
                        get: { state.launchAtLoginStatus.isRegistered },
                        set: actions.setLaunchAtLogin
                    )
                )
                Text(state.launchAtLoginStatus.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Experimental hover") {
                Toggle(
                    "Open the panel from ambient-light hints",
                    isOn: Binding(
                        get: { state.configuration.panelHintsEnabled },
                        set: actions.setPanelHintsEnabled
                    )
                )
                Text(state.panelHintStatus)
                    .foregroundStyle(.secondary)
                Text("Lighting and moving shadows can make this unavailable. It never runs an action.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Calibration") {
                LabeledContent(
                    "Tap acceptance",
                    value: state.tapCalibrationStatus
                )
                LabeledContent(
                    "Left/right detection",
                    value: state.tapRegionCalibrationStatus
                )
                Button("Reset tap-acceptance calibration", role: .destructive) {
                    actions.resetCalibration()
                }
                .disabled(
                    state.tapCalibrationProfile == nil &&
                        state.tapCalibrationStoreWarning == nil
                )
                Button("Reset left/right calibration", role: .destructive) {
                    actions.resetRegionCalibration()
                }
                .disabled(
                    state.tapRegionCalibrationProfile == nil &&
                        state.tapRegionCalibrationStoreWarning == nil
                )
            }

            Section {
                Button("Reset Mactivate Settings", role: .destructive) {
                    actions.reset()
                }
            }
        }
        .formStyle(.grouped)
    }

    private var diagnostics: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Diagnostics")
                .font(.title2.bold())
            HStack {
                statusCard(
                    title: "Palm sensor",
                    value: state.tapStatus,
                    symbol: "hand.tap"
                )
                statusCard(
                    title: "Tap acceptance",
                    value: state.tapCalibrationStatus,
                    symbol: "scope"
                )
                statusCard(
                    title: "Left/right",
                    value: state.tapRegionStatus,
                    symbol: "arrow.left.and.right"
                )
            }
            if let feedback = state.lastTapFeedback {
                GroupBox("Latest tap decision") {
                    VStack(alignment: .leading, spacing: 5) {
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
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            HStack {
                Button("Copy Diagnostics") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(
                        state.diagnosticText,
                        forType: .string
                    )
                }
                Spacer()
                if let warning = state.recentWarning {
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(8)
    }

    private func statusCard(
        title: String,
        value: String,
        symbol: String
    ) -> some View {
        HStack {
            Image(systemName: symbol)
                .font(.title2)
            VStack(alignment: .leading) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.headline)
            }
            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
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
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                slot(0)
                slot(1)
            }
            GridRow {
                slot(2)
                slot(3)
            }
        }
        .padding(12)
        .background(
            Color.black,
            in: UnevenRoundedRectangle(
                cornerRadii: .init(
                    topLeading: 5,
                    bottomLeading: 18,
                    bottomTrailing: 18,
                    topTrailing: 5
                )
            )
        )
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
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 11))
        .overlay {
            RoundedRectangle(cornerRadius: 11)
                .stroke(
                    state.settingsFocusedSlot == index ? .blue : .clear,
                    lineWidth: 2
                )
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
        GroupBox("Step 1 · Calibrate tap acceptance") {
            VStack(alignment: .leading, spacing: 12) {
                Text(
                    "Keep the Mac on a stable surface. Capture five valid single " +
                    "taps for each side and force. Rejected bumps or inconsistent " +
                    "impulses are explained and do not count."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                ForEach(targets, id: \.self) { target in
                    captureRow(target)
                }

                if let feedback = state.lastTapFeedback,
                   feedback.outcome == .candidate {
                    Label(
                        "Impact detected — waiting briefly to resolve single, double, or triple.",
                        systemImage: "waveform"
                    )
                    .font(.caption)
                    .foregroundStyle(.blue)
                } else {
                    Text("After calibration, try a double and triple tap. The latest decision appears in Diagnostics.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let error = state.tapCalibrationError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                HStack {
                    if state.tapCalibrationTarget != nil {
                        Button("Stop capture", action: actions.stopCalibrationCapture)
                    }
                    Spacer()
                    Button("Save calibration", action: actions.saveCalibration)
                        .buttonStyle(.borderedProminent)
                        .disabled(!isComplete || state.tapCalibrationTarget != nil)
                }
            }
            .padding(.top, 4)
        }
    }

    private func captureRow(_ target: TapCalibrationTarget) -> some View {
        let count = state.tapCalibrationDraft.sampleCount(
            side: target.side,
            intensity: target.intensity
        )
        let isActive = state.tapCalibrationTarget == target
        return HStack {
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
    }

    private var isComplete: Bool {
        targets.allSatisfy {
            state.tapCalibrationDraft.sampleCount(
                side: $0.side,
                intensity: $0.intensity
            ) >= TapCalibrationDraft.requiredSamplesPerTarget
        }
    }
}

private struct RegionCalibrationView: View {
    @ObservedObject var state: AppState
    let actions: SettingsActions

    var body: some View {
        GroupBox("Step 2 · Calibrate left/right detection") {
            VStack(alignment: .leading, spacing: 12) {
                Text(
                    "This guided test is completely user-paced. Read the target, " +
                    "then perform that double or triple tap on the requested palm " +
                    "rest. The next target appears only after a valid gesture."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                if let target = state.tapRegionCalibrationTarget {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(
                            "TARGET: \(target.side.rawValue.uppercased()) · " +
                                "\(target.pattern.rawValue.uppercased()) TAP"
                        )
                        .font(.title3.bold())
                        Text(
                            "Perform \(target.pattern.memberCount) taps whenever " +
                                "you are ready."
                        )
                        .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        Color.accentColor.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("region-calibration-target")
                }

                Grid(horizontalSpacing: 16, verticalSpacing: 6) {
                    ForEach(
                        TapRegionCalibrationTarget.ordered,
                        id: \.self
                    ) { target in
                        let count = state.tapRegionCalibrationDraft.sampleCount(
                            target: target
                        )
                        GridRow {
                            Image(
                                systemName: count >= 5
                                    ? "checkmark.circle.fill" : "circle"
                            )
                            .foregroundStyle(
                                count >= 5 ? .green : .secondary
                            )
                            Text(
                                "\(target.side.rawValue.capitalized) palm rest"
                            )
                            Text("\(target.pattern.rawValue.capitalized) tap")
                            Text("\(count)/5")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let error = state.tapRegionCalibrationError {
                    Label(error, systemImage: "arrow.clockwise.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                HStack {
                    if state.tapRegionCalibrationTarget == nil {
                        Button(
                            state.tapRegionCalibrationDraft.totalSampleCount == 0
                                ? "Start guided calibration"
                                : "Restart guided calibration",
                            action: actions.beginRegionCalibration
                        )
                        .buttonStyle(.borderedProminent)
                        .disabled(!state.canCalibrateTapRegion)
                    } else {
                        Button(
                            "Stop calibration",
                            action: actions.stopRegionCalibration
                        )
                    }
                    Spacer()
                    Button(
                        "Qualify and save",
                        action: actions.saveRegionCalibration
                    )
                    .disabled(
                        !state.tapRegionCalibrationDraft.isComplete ||
                            state.tapRegionCalibrationTarget != nil
                    )
                }
            }
            .padding(.top, 4)
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
        VStack(alignment: .leading, spacing: 16) {
            Text("Add an action")
                .font(.title.bold())
            Picker("", selection: $selection) {
                Text("Application").tag(0)
                Text("Web Link").tag(1)
                Text("Shortcut").tag(2)
            }
            .pickerStyle(.segmented)

            Group {
                switch selection {
                case 0:
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Choose an installed application to launch.")
                            .foregroundStyle(.secondary)
                        Button("Choose Application…") {
                            isPresented = false
                            actions.addApplication()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                case 1:
                    Form {
                        TextField("Name", text: $webName)
                        TextField("https://example.com", text: $webAddress)
                        Button("Add Web Link") {
                            if actions.addWebURL(webName, webAddress) {
                                isPresented = false
                            }
                        }
                        .disabled(webName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .formStyle(.grouped)
                default:
                    Form {
                        Picker("Shortcut", selection: $shortcutName) {
                            Text("Choose a Shortcut").tag("")
                            ForEach(state.availableShortcuts, id: \.self) {
                                Text($0).tag($0)
                            }
                        }
                        TextField("Or enter its exact name", text: $shortcutName)
                        HStack {
                            Button("Refresh", action: actions.refreshShortcuts)
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
                    .formStyle(.grouped)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)

            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
            }
        }
        .padding(24)
        .frame(width: 500, height: 340)
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
            .miniaturizable,
            .resizable
        ]
        window.setContentSize(NSSize(width: 830, height: 680))
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
        VStack(spacing: 22) {
            Image(systemName: "hand.tap.fill")
                .font(.system(size: 46))

            Text("Set up Mactivate")
                .font(.largeTitle.bold())
            Text("A quick setup makes palm taps reliable and verifies every action before you rely on it.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 13) {
                setupStep(
                    "Calibrate tap acceptance",
                    complete: state.tapCalibrationProfile != nil
                )
                setupStep(
                    "Calibrate left/right double and triple taps",
                    complete: state.tapRegionCalibrationProfile != nil
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
            .frame(maxWidth: 420, alignment: .leading)

            HStack {
                Button("Set Up Now") {
                    openSettings()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                Button("Finish Later", action: complete)
            }
        }
        .padding(34)
        .frame(width: 540, height: 460)
    }

    private func setupStep(_ title: String, complete: Bool) -> some View {
        Label(
            title,
            systemImage: complete ? "checkmark.circle.fill" : "circle"
        )
        .foregroundStyle(complete ? .green : .primary)
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
