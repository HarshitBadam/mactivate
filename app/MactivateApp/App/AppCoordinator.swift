import AppKit
import MactivateRuntime
import OSLog
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppCoordinator {
    let state: AppState

    let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.mactivate.app",
        category: "runtime"
    )
    let runtime: RuntimeControlling
    let preferencesStore: AppPreferencesStoring
    let executor: ActionExecutor
    let launchAtLogin: LaunchAtLoginManaging
    let panelController: PanelController
    var statusItemController: StatusItemController?
    var settingsWindowController: SettingsWindowController?
    var onboardingWindowController: OnboardingWindowController?
    private var started = false
    var suppressNextCalibrationTapIntent = false

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
            handleTapFeedback(feedback)
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

    func perform(_ action: AppActionDefinition,
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

    func showSettings(focusedSlot: Int? = nil) {
        panelController.dismiss()
        state.settingsFocusedSlot = focusedSlot
        refreshExternalState()
        settingsWindowController?.present()
    }

    func refreshExternalState() {
        state.launchAtLoginStatus = launchAtLogin.status
        refreshStatusItem()
    }

    func refreshStatusItem() {
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
