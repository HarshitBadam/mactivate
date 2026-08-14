import AppKit
import MactivateRuntime
import OSLog
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppCoordinator {
    let state: AppState

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.mactivate.app",
        category: "runtime"
    )
    private let runtime: RuntimeControlling
    private let preferencesStore: AppPreferencesStoring
    private let executor: ActionExecutor
    private let launchAtLogin: LaunchAtLoginManaging
    private let panelController: PanelController
    private var statusItemController: StatusItemController?
    private var settingsWindowController: SettingsWindowController?
    private var onboardingWindowController: OnboardingWindowController?
    private var started = false
    private var suppressNextCalibrationTapIntent = false

    convenience init() throws {
        try self.init(runtime: RuntimeBridge())
    }

    init(runtime: RuntimeControlling,
         preferencesStore: AppPreferencesStoring =
            UserDefaultsAppPreferencesStore(),
         executor: ActionExecutor = ActionExecutor(),
         launchAtLogin: LaunchAtLoginManaging = LaunchAtLoginManager(),
         panelController: PanelController? = nil) {
        self.runtime = runtime
        self.preferencesStore = preferencesStore
        self.executor = executor
        self.launchAtLogin = launchAtLogin
        state = AppState()
        self.panelController = panelController ?? PanelController()
        statusItemController = nil
        settingsWindowController = nil
        onboardingWindowController = nil

        let loadResult = preferencesStore.load()
        state.preferences = loadResult.preferences
        state.configuration = runtime.currentConfiguration
        state.snapshot = runtime.currentSnapshot
        state.tapCalibrationProfile = runtime.currentTapCalibrationProfile
        state.tapRegionCalibrationProfile =
            runtime.currentTapRegionCalibrationProfile
        state.tapCalibrationStoreWarning = runtime.tapCalibrationWarning
        state.tapRegionCalibrationStoreWarning =
            runtime.tapRegionCalibrationWarning
        state.launchAtLoginStatus = launchAtLogin.status
        state.recentWarning = loadResult.warning ??
            runtime.tapCalibrationWarning ??
            runtime.tapRegionCalibrationWarning

        let viewActions = AppViewActions(
            performAction: { [weak self] action in
                self?.perform(action, invocation: .quickAction)
            },
            showSettings: { [weak self] slot in
                self?.showSettings(focusedSlot: slot)
            }
        )
        self.panelController.setRootView(AnyView(
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
            if state.snapshot.lifecycle != snapshot.lifecycle {
                logger.notice(
                    "Runtime state changed to \(String(describing: snapshot.lifecycle), privacy: .public)"
                )
            }
            state.snapshot = snapshot
            if snapshot.lifecycle == .suspended {
                panelController.closeForSleep()
            }
        case .tapFeedback(let feedback):
            state.lastTapFeedback = feedback
            if let target = state.tapRegionCalibrationTarget,
               feedback.outcome != .candidate {
                if isAcceptedForRegionCalibration(feedback.outcome) {
                    if case .dispatched = feedback.outcome {
                        suppressNextCalibrationTapIntent = true
                    }
                    do {
                        try state.tapRegionCalibrationDraft.record(
                            feedback,
                            target: target
                        )
                        state.tapRegionCalibrationError = nil
                        advanceRegionCalibration(after: target)
                    } catch {
                        state.tapRegionCalibrationError =
                            String(describing: error)
                    }
                } else if case .rejected(let reason) = feedback.outcome {
                    state.tapRegionCalibrationError =
                        "Gesture rejected. \(reason.guidance)"
                } else if case .spatialUnavailable(_, let reason) =
                            feedback.outcome {
                    state.tapRegionCalibrationError = reason.message
                }
            } else if let target = state.tapCalibrationTarget,
                      feedback.outcome != .candidate {
                do {
                    try state.tapCalibrationDraft.record(
                        feedback,
                        side: target.side,
                        intensity: target.intensity
                    )
                    state.tapCalibrationError = nil
                    if state.tapCalibrationDraft.sampleCount(
                        side: target.side,
                        intensity: target.intensity
                    ) >= TapCalibrationDraft.requiredSamplesPerTarget {
                        state.tapCalibrationTarget = nil
                    }
                } catch {
                    state.tapCalibrationError = String(describing: error)
                }
            }
        case .intent(.showPanel):
            guard state.tapCalibrationTarget == nil,
                  state.tapRegionCalibrationTarget == nil else { break }
            panelController.showPassiveHint()
        case .intent(.performAction(let identifier, let trigger)):
            if suppressNextCalibrationTapIntent {
                suppressNextCalibrationTapIntent = false
                break
            }
            guard state.tapCalibrationTarget == nil,
                  state.tapRegionCalibrationTarget == nil else { break }
            guard let action = state.action(for: identifier) else {
                state.actionError = AppActionError.unknownAction.localizedDescription
                return
            }
            perform(action, invocation: .tap(trigger))
        case .warning(.configuration(let message)):
            logger.error(
                "Configuration warning: \(message, privacy: .public)"
            )
            state.recentWarning = message
        case .warning(.source(_, let message)):
            logger.error("Sensor warning: \(message, privacy: .public)")
            state.recentWarning = message
        }
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
            setSpatialTapBinding: { [weak self] identifier, gesture in
                self?.setSpatialTapBinding(identifier, gesture: gesture)
            },
            setPanelHintsEnabled: { [weak self] enabled in
                self?.setPanelHintsEnabled(enabled)
            },
            setQuickAction: { [weak self] index, identifier in
                self?.setQuickAction(index: index, identifier: identifier)
            },
            addApplication: { [weak self] in
                self?.addApplication() ?? false
            },
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
            beginCalibrationCapture: { [weak self] target in
                self?.beginCalibrationCapture(target)
            },
            stopCalibrationCapture: { [weak self] in
                self?.state.tapCalibrationTarget = nil
            },
            saveCalibration: { [weak self] in
                self?.saveCalibration()
            },
            resetCalibration: { [weak self] in
                self?.resetCalibration()
            },
            beginRegionCalibration: { [weak self] in
                self?.beginRegionCalibration()
            },
            stopRegionCalibration: { [weak self] in
                self?.state.tapRegionCalibrationTarget = nil
            },
            saveRegionCalibration: { [weak self] in
                self?.saveRegionCalibration()
            },
            resetRegionCalibration: { [weak self] in
                self?.resetRegionCalibration()
            },
            testAction: { [weak self] identifier in
                guard let self, let action = self.state.action(for: identifier) else {
                    return
                }
                self.perform(action, invocation: .quickAction)
            },
            reset: { [weak self] in self?.resetSettings() }
        )
    }

    private func beginCalibrationCapture(_ target: TapCalibrationTarget) {
        state.tapRegionCalibrationTarget = nil
        state.tapCalibrationTarget = nil
        state.tapCalibrationDraft.reset(
            side: target.side,
            intensity: target.intensity
        )
        state.tapCalibrationError = nil
        state.lastTapFeedback = nil
        state.tapCalibrationTarget = target
    }

    private func saveCalibration() {
        state.tapCalibrationTarget = nil
        state.tapRegionCalibrationTarget = nil
        do {
            let profile = try state.tapCalibrationDraft.buildProfile()
            try runtime.applyTapCalibration(profile)
            state.tapCalibrationProfile = profile
            state.tapCalibrationError = nil
            clearTapCalibrationStoreWarning()
        } catch {
            state.tapCalibrationError = String(describing: error)
        }
    }

    private func resetCalibration() {
        do {
            state.tapRegionCalibrationTarget = nil
            try runtime.resetTapCalibration()
            state.tapCalibrationDraft.reset()
            state.tapCalibrationTarget = nil
            state.tapCalibrationProfile = nil
            state.tapCalibrationError = nil
            clearTapCalibrationStoreWarning()
        } catch {
            state.tapCalibrationError = error.localizedDescription
        }
    }

    private func beginRegionCalibration() {
        guard state.canCalibrateTapRegion else {
            state.tapRegionCalibrationError =
                "Complete tap-acceptance calibration and connect the gyroscope first."
            return
        }
        state.tapCalibrationTarget = nil
        state.tapRegionCalibrationDraft.reset()
        state.tapRegionCalibrationError = nil
        state.lastTapFeedback = nil
        state.tapRegionCalibrationTarget =
            TapRegionCalibrationTarget.ordered.first
    }

    private func advanceRegionCalibration(
        after target: TapRegionCalibrationTarget
    ) {
        let required =
            TapRegionCalibrationDraft.requiredGesturesPerTarget
        guard state.tapRegionCalibrationDraft.sampleCount(target: target) >=
                required else {
            return
        }
        if let next = TapRegionCalibrationTarget.ordered.first(where: {
            state.tapRegionCalibrationDraft.sampleCount(target: $0) < required
        }) {
            state.tapRegionCalibrationTarget = next
        } else {
            state.tapRegionCalibrationTarget = nil
            saveRegionCalibration()
        }
    }

    private func saveRegionCalibration() {
        state.tapRegionCalibrationTarget = nil
        do {
            let result = try state.tapRegionCalibrationDraft.buildProfile()
            try runtime.applyTapRegionCalibration(result.profile)
            state.tapRegionCalibrationProfile = result.profile
            state.tapRegionCalibrationError = nil
            clearTapRegionCalibrationStoreWarning()
        } catch {
            state.tapRegionCalibrationError = String(describing: error)
        }
    }

    private func resetRegionCalibration() {
        do {
            state.tapCalibrationTarget = nil
            try runtime.resetTapRegionCalibration()
            state.tapRegionCalibrationDraft.reset()
            state.tapRegionCalibrationTarget = nil
            state.tapRegionCalibrationProfile = nil
            state.tapRegionCalibrationError = nil
            clearTapRegionCalibrationStoreWarning()
        } catch {
            state.tapRegionCalibrationError = error.localizedDescription
        }
    }

    private func clearTapCalibrationStoreWarning() {
        if state.recentWarning == state.tapCalibrationStoreWarning {
            state.recentWarning = nil
        }
        state.tapCalibrationStoreWarning = nil
    }

    private func clearTapRegionCalibrationStoreWarning() {
        if state.recentWarning == state.tapRegionCalibrationStoreWarning {
            state.recentWarning = nil
        }
        state.tapRegionCalibrationStoreWarning = nil
    }

    private func isAcceptedForRegionCalibration(
        _ outcome: TapFeedbackOutcome
    ) -> Bool {
        switch outcome {
        case .acceptedNonActionable, .acceptedUnmapped, .dispatched:
            return true
        case .spatialUnavailable(_, let reason):
            return reason != .tapCalibrationRequired
        case .candidate, .rejected, .duplicate:
            return false
        }
    }

    private func showSettings(focusedSlot: Int? = nil) {
        panelController.dismiss()
        state.settingsFocusedSlot = focusedSlot
        refreshExternalState()
        settingsWindowController?.present()
    }

    private func refreshExternalState() {
        state.launchAtLoginStatus = launchAtLogin.status
        refreshStatusItem()
    }

    func setSpatialTapBinding(
        _ identifier: ActionIdentifier?,
        gesture: PalmTapGesture
    ) {
        do {
            try runtime.setSpatialTapBinding(identifier, for: gesture)
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
        if state.settingsFocusedSlot == index {
            state.settingsFocusedSlot = nil
        }
    }

    @discardableResult
    private func addApplication() -> Bool {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.application]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.prompt = "Add Application"
        guard openPanel.runModal() == .OK else { return false }
        guard let url = openPanel.url,
              let bundle = Bundle(url: url),
              let identifier = bundle.bundleIdentifier else {
            state.actionError = "The selected application has no bundle identifier."
            return false
        }
        let name = bundle.object(
            forInfoDictionaryKey: "CFBundleDisplayName"
        ) as? String ?? bundle.object(
            forInfoDictionaryKey: "CFBundleName"
        ) as? String ?? url.deletingPathExtension().lastPathComponent
        return addAction(
            .application(name: name, bundleIdentifier: identifier)
        )
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

        for gesture in PalmTapGesture.allCases
        where state.configuration.spatialTapBindings[gesture] == identifier {
            setSpatialTapBinding(nil, gesture: gesture)
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
