import AppKit
import MactivateRuntime
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppCoordinator {
    let state: AppState

    private let runtime: RuntimeControlling
    private let preferencesStore: AppPreferencesStoring
    private let executor: ActionExecutor
    private let launchAtLogin: LaunchAtLoginManaging
    private let panelController: PanelController
    private var statusItemController: StatusItemController?
    private var settingsWindowController: SettingsWindowController?
    private var onboardingWindowController: OnboardingWindowController?
    private var started = false

    convenience init() throws {
        try self.init(runtime: RuntimeBridge())
    }

    init(runtime: RuntimeControlling,
         preferencesStore: AppPreferencesStoring =
            UserDefaultsAppPreferencesStore(),
         executor: ActionExecutor = ActionExecutor(),
         launchAtLogin: LaunchAtLoginManaging = LaunchAtLoginManager()) {
        self.runtime = runtime
        self.preferencesStore = preferencesStore
        self.executor = executor
        self.launchAtLogin = launchAtLogin
        state = AppState()
        panelController = PanelController()
        statusItemController = nil
        settingsWindowController = nil
        onboardingWindowController = nil

        let loadResult = preferencesStore.load()
        state.preferences = loadResult.preferences
        state.configuration = runtime.currentConfiguration
        state.snapshot = runtime.currentSnapshot
        state.launchAtLoginStatus = launchAtLogin.status
        state.recentWarning = loadResult.warning

        let viewActions = AppViewActions(
            performAction: { [weak self] action in
                self?.perform(action, invocation: .quickAction)
            },
            showSettings: { [weak self] in self?.showSettings() }
        )
        panelController.setRootView(AnyView(
            PanelContentView(state: state, actions: viewActions)
        ))

        let settingsActions = makeSettingsActions()
        settingsWindowController = SettingsWindowController(
            state: state,
            actions: settingsActions
        )
        onboardingWindowController = OnboardingWindowController(
            state: state,
            openSettings: { [weak self] in self?.showSettings() },
            complete: { [weak self] in self?.completeOnboarding() }
        )
        statusItemController = StatusItemController(actions: StatusItemActions(
            togglePanel: { [weak self] screen in
                self?.panelController.toggleInteractive(on: screen)
            },
            showSettings: { [weak self] in self?.showSettings() },
            refreshExternalState: { [weak self] in
                self?.refreshExternalState()
            },
            setPanelHintsEnabled: { [weak self] enabled in
                self?.setPanelHintsEnabled(enabled)
            },
            setLaunchAtLoginEnabled: { [weak self] enabled in
                self?.setLaunchAtLoginEnabled(enabled)
            },
            quit: { [weak self] in self?.quit() }
        ))

        runtime.outputHandler = { [weak self] output in
            self?.handle(output)
        }
        refreshStatusItem()
    }

    func start() {
        guard !started else { return }
        started = true
        runtime.start()
        refreshShortcuts()
        if !state.preferences.onboardingCompleted {
            onboardingWindowController?.present()
        }
    }

    func stop() {
        guard started else { return }
        started = false
        runtime.stop()
        panelController.dismiss()
    }

    func reopen() {
        panelController.showInteractive(on: statusItemController?.screen)
    }

    private func handle(_ output: RuntimeOutput) {
        switch output {
        case .statusChanged(let snapshot):
            state.snapshot = snapshot
            if snapshot.lifecycle == .suspended {
                panelController.closeForSleep()
            }
        case .intent(.showPanel):
            panelController.showPassiveHint()
        case .intent(.performAction(let identifier, let trigger)):
            guard let action = state.action(for: identifier) else {
                state.actionError = AppActionError.unknownAction.localizedDescription
                return
            }
            perform(action, invocation: .tap(trigger))
        case .warning(.configuration(let message)):
            state.recentWarning = message
        case .warning(.source(_, let message)):
            state.recentWarning = message
        }
        state.configuration = runtime.currentConfiguration
        refreshStatusItem()
    }

    private func perform(_ action: AppActionDefinition,
                         invocation: ActionInvocation) {
        state.actionError = nil
        executor.execute(action, invocation: invocation) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(.executed):
                if case .showPanel = action.kind {
                    self.panelController.showInteractive()
                } else if case .quickAction = invocation {
                    self.panelController.dismiss()
                }
            case .success(.skippedDuplicate):
                break
            case .failure(let error):
                self.state.actionError = error.localizedDescription
            }
        }
    }

    private func makeSettingsActions() -> SettingsActions {
        SettingsActions(
            setTapBinding: { [weak self] identifier, pattern in
                self?.setTapBinding(identifier, pattern: pattern)
            },
            setPanelHintsEnabled: { [weak self] enabled in
                self?.setPanelHintsEnabled(enabled)
            },
            setQuickAction: { [weak self] index, identifier in
                self?.setQuickAction(index: index, identifier: identifier)
            },
            addApplication: { [weak self] in self?.addApplication() },
            addWebURL: { [weak self] name, value in
                self?.addWebURL(name: name, value: value) ?? false
            },
            addShortcut: { [weak self] name in
                self?.addShortcut(name: name) ?? false
            },
            deleteAction: { [weak self] identifier in
                self?.deleteAction(identifier)
            },
            refreshShortcuts: { [weak self] in
                self?.refreshShortcuts(surfaceAsActionError: true)
            },
            setLaunchAtLogin: { [weak self] enabled in
                self?.setLaunchAtLoginEnabled(enabled)
            },
            reset: { [weak self] in self?.resetSettings() }
        )
    }

    private func showSettings() {
        panelController.dismiss()
        refreshExternalState()
        settingsWindowController?.present()
    }

    private func refreshExternalState() {
        state.launchAtLoginStatus = launchAtLogin.status
        refreshStatusItem()
    }

    func setTapBinding(_ identifier: ActionIdentifier?,
                       pattern: TapPattern) {
        do {
            try runtime.setTapBinding(identifier, for: pattern)
            state.configuration = runtime.currentConfiguration
            refreshStatusItem()
        } catch {
            state.recentWarning = error.localizedDescription
        }
    }

    private func setPanelHintsEnabled(_ enabled: Bool) {
        do {
            try runtime.setPanelHintsEnabled(enabled)
            state.configuration = runtime.currentConfiguration
            refreshStatusItem()
        } catch {
            state.recentWarning = error.localizedDescription
        }
    }

    func setQuickAction(index: Int,
                        identifier: ActionIdentifier?) {
        guard (0..<AppPreferences.quickActionCount).contains(index) else {
            return
        }
        var updated = state.preferences
        updated.quickActionIDs = updated.normalizedQuickActionIDs
        updated.quickActionIDs[index] = identifier
        savePreferences(updated)
    }

    private func addApplication() {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.application]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.prompt = "Add Application"
        guard openPanel.runModal() == .OK,
              let url = openPanel.url,
              let bundle = Bundle(url: url),
              let identifier = bundle.bundleIdentifier else {
            state.actionError = "The selected application has no bundle identifier."
            return
        }
        let name = bundle.object(
            forInfoDictionaryKey: "CFBundleDisplayName"
        ) as? String ?? bundle.object(
            forInfoDictionaryKey: "CFBundleName"
        ) as? String ?? url.deletingPathExtension().lastPathComponent
        addAction(.application(name: name, bundleIdentifier: identifier))
    }

    @discardableResult
    func addWebURL(name: String, value: String) -> Bool {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: cleanValue) else {
            state.actionError = AppActionError.invalidURL.localizedDescription
            return false
        }
        let action = AppActionDefinition.webURL(name: cleanName, url: url)
        guard action.isValid else {
            state.actionError = AppActionError.invalidURL.localizedDescription
            return false
        }
        return addAction(action)
    }

    @discardableResult
    func addShortcut(name: String) -> Bool {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let action = AppActionDefinition.shortcut(name: cleanName)
        guard action.isValid else {
            state.actionError = "Enter a Shortcut name."
            return false
        }
        return addAction(action)
    }

    @discardableResult
    private func addAction(_ action: AppActionDefinition) -> Bool {
        var updated = state.preferences
        updated.actions.append(action)
        if let emptyIndex = updated.normalizedQuickActionIDs.firstIndex(where: {
            $0 == nil
        }) {
            updated.quickActionIDs = updated.normalizedQuickActionIDs
            updated.quickActionIDs[emptyIndex] = action.id
        }
        if savePreferences(updated) {
            state.actionError = nil
            return true
        }
        return false
    }

    func deleteAction(_ identifier: ActionIdentifier) {
        var updated = state.preferences
        updated.actions.removeAll { $0.id == identifier }
        updated.quickActionIDs = updated.normalizedQuickActionIDs.map {
            $0 == identifier ? nil : $0
        }
        guard savePreferences(updated) else { return }

        for pattern in TapPattern.allCases
        where state.configuration.tapBindings[pattern] == identifier {
            setTapBinding(nil, pattern: pattern)
        }
    }

    @discardableResult
    private func savePreferences(_ preferences: AppPreferences) -> Bool {
        do {
            try preferencesStore.save(preferences)
            state.preferences = preferences
            return true
        } catch {
            state.recentWarning = error.localizedDescription
            state.actionError = error.localizedDescription
            return false
        }
    }

    private func refreshShortcuts(surfaceAsActionError: Bool = false) {
        executor.listShortcuts { [weak self] result in
            switch result {
            case .success(let names):
                self?.state.availableShortcuts = names
                if surfaceAsActionError {
                    self?.state.actionError = nil
                }
            case .failure(let error):
                self?.state.recentWarning = error.localizedDescription
                if surfaceAsActionError {
                    self?.state.actionError = error.localizedDescription
                }
            }
        }
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        do {
            try launchAtLogin.setEnabled(enabled)
        } catch {
            state.recentWarning = error.localizedDescription
        }
        state.launchAtLoginStatus = launchAtLogin.status
        refreshStatusItem()
    }

    func resetSettings() {
        do {
            try runtime.resetConfiguration()
            state.configuration = runtime.currentConfiguration
        } catch {
            state.recentWarning = error.localizedDescription
        }
        var defaults = AppPreferences.default
        defaults.onboardingCompleted = true
        if savePreferences(defaults) {
            state.actionError = nil
        }
        refreshStatusItem()
    }

    private func completeOnboarding() {
        var updated = state.preferences
        updated.onboardingCompleted = true
        if savePreferences(updated) {
            onboardingWindowController?.close()
        }
    }

    private func refreshStatusItem() {
        statusItemController?.update(
            snapshot: state.snapshot,
            configuration: state.configuration,
            launchAtLoginStatus: state.launchAtLoginStatus
        )
    }

    private func quit() {
        stop()
        NSApp.terminate(nil)
    }
}
