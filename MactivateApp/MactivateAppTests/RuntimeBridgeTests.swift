import MactivateRuntime
import XCTest
@testable import MactivateApp

@MainActor
final class RuntimeBridgeTests: XCTestCase {
    func testCoordinatorOwnsOneRuntimeLifecycle() {
        let runtime = FakeRuntime()
        let coordinator = makeCoordinator(runtime: runtime)

        coordinator.start()
        coordinator.start()
        coordinator.stop()
        coordinator.stop()

        XCTAssertEqual(runtime.startCount, 1)
        XCTAssertEqual(runtime.stopCount, 1)
    }

    func testStatusOutputUpdatesObservableState() {
        let runtime = FakeRuntime()
        let coordinator = makeCoordinator(runtime: runtime)
        let snapshot = RuntimeSnapshot(
            lifecycle: .running,
            tap: .available(measuredRateHz: 796),
            panelHint: .tooDim
        )

        runtime.outputHandler?(.statusChanged(snapshot))

        XCTAssertEqual(coordinator.state.snapshot, snapshot)
        XCTAssertEqual(coordinator.state.tapStatus, "Palm taps ready · 796 Hz")
        XCTAssertEqual(
            coordinator.state.panelHintStatus,
            "Hover unavailable in dim light"
        )
    }

    func testStatusOutputDoesNotSynchronouslyReadRuntimeConfiguration() {
        let runtime = FakeRuntime()
        _ = makeCoordinator(runtime: runtime)
        let readsAfterInitialization = runtime.configurationReadCount

        runtime.outputHandler?(.statusChanged(RuntimeSnapshot(
            lifecycle: .starting,
            tap: .warmingUp,
            panelHint: .disabled
        )))

        XCTAssertEqual(runtime.configurationReadCount, readsAfterInitialization)
    }

    func testWarningOutputIsVisible() {
        let runtime = FakeRuntime()
        let coordinator = makeCoordinator(runtime: runtime)

        runtime.outputHandler?(.warning(.configuration("bad settings")))

        XCTAssertEqual(coordinator.state.recentWarning, "bad settings")
    }

    func testUnavailableReasonsAppearInDiagnostics() {
        let runtime = FakeRuntime()
        let coordinator = makeCoordinator(runtime: runtime)
        runtime.outputHandler?(.statusChanged(RuntimeSnapshot(
            lifecycle: .running,
            tap: .unavailable(reason: "accelerometer missing"),
            panelHint: .unavailable(reason: "ALS missing")
        )))

        XCTAssertTrue(
            coordinator.state.diagnosticText.contains("accelerometer missing")
        )
        XCTAssertTrue(coordinator.state.diagnosticText.contains("ALS missing"))
    }

    func testUnknownActionIdentifierFailsClosedWithoutExecuting() {
        let runtime = FakeRuntime()
        let coordinator = makeCoordinator(runtime: runtime)
        let trigger = TapTrigger(
            eventID: RuntimeEventID(
                sessionID: UUID(),
                classifierEventID: "tap-1"
            ),
            pattern: .single,
            sensorTimestamp: 1
        )

        runtime.outputHandler?(.intent(.performAction(
            id: "action.does-not-exist",
            trigger: trigger
        )))

        XCTAssertNotNil(coordinator.state.actionError)
    }

    func testSetTapBindingUpdatesConfigurationOnSuccess() {
        let runtime = FakeRuntime()
        let coordinator = makeCoordinator(runtime: runtime)

        coordinator.setTapBinding("builtin.show-panel", pattern: .double)

        XCTAssertEqual(
            coordinator.state.configuration.tapBindings.double,
            "builtin.show-panel"
        )
        XCTAssertNil(coordinator.state.recentWarning)
    }

    func testSetTapBindingSurfacesRuntimeFailureAsWarning() {
        let runtime = FakeRuntime()
        runtime.setTapBindingError = TestFailure("rejected")
        let coordinator = makeCoordinator(runtime: runtime)

        coordinator.setTapBinding("builtin.show-panel", pattern: .single)

        XCTAssertEqual(coordinator.state.recentWarning, "rejected")
    }

    func testSetQuickActionPersistsIntoNormalizedSlot() {
        let runtime = FakeRuntime()
        let coordinator = makeCoordinator(runtime: runtime)

        coordinator.setQuickAction(index: 1, identifier: "builtin.show-panel")

        XCTAssertEqual(
            coordinator.state.preferences.normalizedQuickActionIDs[1],
            "builtin.show-panel"
        )
    }

    func testSetQuickActionIgnoresOutOfRangeIndex() {
        let runtime = FakeRuntime()
        let coordinator = makeCoordinator(runtime: runtime)

        coordinator.setQuickAction(index: 99, identifier: "builtin.show-panel")

        XCTAssertTrue(
            coordinator.state.preferences.normalizedQuickActionIDs
                .allSatisfy { $0 == nil }
        )
    }

    func testAddWebURLPersistsAndFillsAnEmptyQuickActionSlot() {
        let runtime = FakeRuntime()
        let coordinator = makeCoordinator(runtime: runtime)

        let added = coordinator.addWebURL(
            name: "Example",
            value: "https://example.com"
        )

        XCTAssertTrue(added)
        XCTAssertEqual(coordinator.state.preferences.actions.count, 1)
        XCTAssertEqual(
            coordinator.state.preferences.normalizedQuickActionIDs[0],
            coordinator.state.preferences.actions.first?.id
        )
    }

    func testAddWebURLRejectsNonHTTPScheme() {
        let runtime = FakeRuntime()
        let coordinator = makeCoordinator(runtime: runtime)

        let added = coordinator.addWebURL(name: "Bad", value: "file:///tmp")

        XCTAssertFalse(added)
        XCTAssertTrue(coordinator.state.preferences.actions.isEmpty)
        XCTAssertNotNil(coordinator.state.actionError)
    }

    func testAddShortcutRejectsBlankName() {
        let runtime = FakeRuntime()
        let coordinator = makeCoordinator(runtime: runtime)

        let added = coordinator.addShortcut(name: "   ")

        XCTAssertFalse(added)
        XCTAssertTrue(coordinator.state.preferences.actions.isEmpty)
    }

    func testDeletingAnActionClearsItsQuickActionSlotAndTapBindings() {
        let runtime = FakeRuntime()
        let coordinator = makeCoordinator(runtime: runtime)
        coordinator.addShortcut(name: "Focus")
        let action = coordinator.state.preferences.actions[0]
        coordinator.setTapBinding(action.id, pattern: .single)

        coordinator.deleteAction(action.id)

        XCTAssertTrue(coordinator.state.preferences.actions.isEmpty)
        XCTAssertTrue(
            coordinator.state.preferences.normalizedQuickActionIDs
                .allSatisfy { $0 == nil }
        )
        XCTAssertNil(coordinator.state.configuration.tapBindings.single)
    }

    func testResetSettingsRestoresRuntimeAndAppDefaults() {
        let runtime = FakeRuntime()
        let coordinator = makeCoordinator(runtime: runtime)
        coordinator.addShortcut(name: "Focus")
        coordinator.setTapBinding("builtin.show-panel", pattern: .triple)

        coordinator.resetSettings()

        XCTAssertEqual(coordinator.state.configuration, .default)
        XCTAssertTrue(coordinator.state.preferences.actions.isEmpty)
        XCTAssertTrue(coordinator.state.preferences.onboardingCompleted)
    }

    func testSetLaunchAtLoginEnabledUpdatesStatusFromManager() {
        let runtime = FakeRuntime()
        let launchAtLogin = TestLaunchAtLogin()
        let coordinator = makeCoordinator(
            runtime: runtime,
            launchAtLogin: launchAtLogin
        )

        coordinator.setLaunchAtLoginEnabled(true)

        XCTAssertEqual(coordinator.state.launchAtLoginStatus, .enabled)
    }

    func testSetLaunchAtLoginFailureSurfacesWarningWithoutCrashing() {
        let runtime = FakeRuntime()
        let launchAtLogin = TestLaunchAtLogin()
        launchAtLogin.errorToThrow = TestFailure("denied")
        let coordinator = makeCoordinator(
            runtime: runtime,
            launchAtLogin: launchAtLogin
        )

        coordinator.setLaunchAtLoginEnabled(true)

        XCTAssertEqual(coordinator.state.recentWarning, "denied")
    }

    private func makeCoordinator(
        runtime: FakeRuntime,
        launchAtLogin: TestLaunchAtLogin = TestLaunchAtLogin()
    ) -> AppCoordinator {
        var preferences = AppPreferences.default
        preferences.onboardingCompleted = true
        return AppCoordinator(
            runtime: runtime,
            preferencesStore: InMemoryAppPreferencesStore(
                preferences: preferences
            ),
            executor: ActionExecutor(
                workspace: TestWorkspace(),
                shortcuts: TestShortcuts()
            ),
            launchAtLogin: launchAtLogin
        )
    }
}

private struct TestFailure: Error, LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}

private final class FakeRuntime: RuntimeControlling {
    var outputHandler: ((RuntimeOutput) -> Void)?
    private var configuration = RuntimeConfiguration.default
    var currentSnapshot = RuntimeSnapshot()
    private(set) var configurationReadCount = 0
    var startCount = 0
    var stopCount = 0
    var setTapBindingError: Error?

    var currentConfiguration: RuntimeConfiguration {
        configurationReadCount += 1
        return configuration
    }

    func start() {
        startCount += 1
    }

    func stop() {
        stopCount += 1
    }

    func setTapBinding(_ action: ActionIdentifier?,
                       for pattern: TapPattern) throws {
        if let setTapBindingError {
            throw setTapBindingError
        }
        configuration.tapBindings[pattern] = action
    }

    func setPanelHintsEnabled(_ enabled: Bool) throws {
        configuration.panelHintsEnabled = enabled
    }

    func resetConfiguration() throws {
        configuration = .default
    }
}

private final class TestWorkspace: WorkspaceOpening {
    func openApplication(
        bundleIdentifier: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        completion(.success(()))
    }

    func openURL(
        _ url: URL,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        completion(.success(()))
    }
}

private final class TestShortcuts: ShortcutRunning {
    func run(
        name: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        completion(.success(()))
    }

    func list(
        completion: @escaping (Result<[String], Error>) -> Void
    ) {
        completion(.success([]))
    }
}

private final class TestLaunchAtLogin: LaunchAtLoginManaging {
    var status: LaunchAtLoginStatus = .disabled
    var errorToThrow: Error?

    func setEnabled(_ enabled: Bool) throws {
        if let errorToThrow {
            throw errorToThrow
        }
        status = enabled ? .enabled : .disabled
    }
}
