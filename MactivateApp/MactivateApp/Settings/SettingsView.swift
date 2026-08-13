import AppKit
import MactivateRuntime
import SwiftUI

struct SettingsActions {
    let setTapBinding: (ActionIdentifier?, TapPattern) -> Void
    let setPanelHintsEnabled: (Bool) -> Void
    let setQuickAction: (Int, ActionIdentifier?) -> Void
    let addApplication: () -> Void
    let addWebURL: (String, String) -> Bool
    let addShortcut: (String) -> Bool
    let deleteAction: (ActionIdentifier) -> Void
    let refreshShortcuts: () -> Void
    let setLaunchAtLogin: (Bool) -> Void
    let reset: () -> Void
}

struct SettingsView: View {
    @ObservedObject var state: AppState
    let actions: SettingsActions

    @State private var webName = ""
    @State private var webAddress = "https://"
    @State private var shortcutName = ""

    var body: some View {
        TabView {
            gestures
                .tabItem { Label("Gestures", systemImage: "hand.tap") }
            quickActions
                .tabItem { Label("Quick Actions", systemImage: "square.grid.2x2") }
            general
                .tabItem { Label("General", systemImage: "gearshape") }
            diagnostics
                .tabItem { Label("Diagnostics", systemImage: "waveform.path.ecg") }
        }
        .padding(20)
        .frame(minWidth: 620, minHeight: 470)
    }

    private var gestures: some View {
        Form {
            if let warning = state.recentWarning {
                Section {
                    Label(warning, systemImage: "exclamationmark.circle")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Palm-rest taps") {
                bindingPicker("Single tap", pattern: .single)
                bindingPicker("Double tap", pattern: .double)
                bindingPicker("Triple tap", pattern: .triple)
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
                Text(
                    "Lighting and moving shadows can make this unavailable or " +
                    "open the panel accidentally. It never executes an action."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var quickActions: some View {
        Form {
            if let error = state.actionError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .accessibilityLabel("Action error: \(error)")
                }
            }

            Section("Panel slots") {
                ForEach(0..<AppPreferences.quickActionCount, id: \.self) { index in
                    Picker(
                        "Slot \(index + 1)",
                        selection: Binding(
                            get: {
                                state.preferences.normalizedQuickActionIDs[index]
                            },
                            set: { actions.setQuickAction(index, $0) }
                        )
                    ) {
                        Text("None").tag(ActionIdentifier?.none)
                        ForEach(state.actions) { action in
                            Text(action.name).tag(Optional(action.id))
                        }
                    }
                }
            }

            Section("Action library") {
                ForEach(state.preferences.actions) { action in
                    HStack {
                        Label(action.name, systemImage: action.kind.symbolName)
                        Spacer()
                        Button(role: .destructive) {
                            actions.deleteAction(action.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Delete \(action.name)")
                    }
                }
                Button("Add Application…", action: actions.addApplication)
            }

            Section("Add web link") {
                TextField("Name", text: $webName)
                TextField("http:// or https://", text: $webAddress)
                Button("Add Web Link") {
                    if actions.addWebURL(webName, webAddress) {
                        webName = ""
                        webAddress = "https://"
                    }
                }
                .disabled(webName.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Section("Add macOS Shortcut") {
                HStack {
                    Picker("Shortcut", selection: $shortcutName) {
                        Text("Choose a Shortcut").tag("")
                        ForEach(state.availableShortcuts, id: \.self) {
                            Text($0).tag($0)
                        }
                    }
                    Button {
                        actions.refreshShortcuts()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh Shortcuts")
                }
                TextField("Or enter its exact name", text: $shortcutName)
                Button("Add Shortcut") {
                    if actions.addShortcut(shortcutName) {
                        shortcutName = ""
                    }
                }
                .disabled(shortcutName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .formStyle(.grouped)
    }

    private var general: some View {
        Form {
            if let warning = state.recentWarning {
                Section {
                    Label(warning, systemImage: "exclamationmark.circle")
                        .foregroundStyle(.secondary)
                }
            }

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

            Section("Status") {
                Label(state.tapStatus, systemImage: "hand.tap")
                Label(state.panelHintStatus, systemImage: "sun.min")
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
            Text(
                "Sensor availability is reported independently. The menu-bar " +
                "panel remains available even when a sensor path fails."
            )
            .foregroundStyle(.secondary)
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

    private func bindingPicker(_ title: String,
                               pattern: TapPattern) -> some View {
        Picker(
            title,
            selection: Binding(
                get: { state.configuration.tapBindings[pattern] },
                set: { actions.setTapBinding($0, pattern) }
            )
        ) {
            Text("None").tag(ActionIdentifier?.none)
            ForEach(state.actions) { action in
                Text(action.name).tag(Optional(action.id))
            }
            if let binding = state.configuration.tapBindings[pattern],
               state.action(for: binding) == nil {
                Text("Missing action").tag(Optional(binding))
            }
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
            .miniaturizable,
            .resizable
        ]
        window.setContentSize(NSSize(width: 660, height: 520))
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
        VStack(spacing: 20) {
            Image(systemName: "hand.tap.fill")
                .font(.system(size: 46))
                .foregroundStyle(.primary)

            Text("Welcome to Mactivate")
                .font(.largeTitle.bold())

            VStack(alignment: .leading, spacing: 12) {
                Label(
                    "Single, double, and triple palm-rest taps can run your actions.",
                    systemImage: "1.circle"
                )
                Label(
                    "The menu-bar hand icon always opens the panel.",
                    systemImage: "2.circle"
                )
                Label(
                    "Experimental hover only opens the panel and depends on lighting.",
                    systemImage: "3.circle"
                )
            }
            .frame(maxWidth: 390, alignment: .leading)

            Text(state.tapStatus)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Configure Actions") {
                    openSettings()
                    complete()
                }
                Button("Continue") {
                    complete()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(32)
        .frame(width: 500, height: 390)
    }
}

@MainActor
final class OnboardingWindowController: NSWindowController {
    init(state: AppState,
         openSettings: @escaping () -> Void,
         complete: @escaping () -> Void) {
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
