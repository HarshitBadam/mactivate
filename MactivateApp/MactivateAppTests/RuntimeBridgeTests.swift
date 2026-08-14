import AppKit
import MactuationCore
import MactivateRuntime
import SwiftUI
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

    func testRuntimeBridgePersistsAndResetsRegionProfileIndependently()
        throws {
        let tapStore = InMemoryTapCalibrationProfileStore()
        let regionStore = InMemoryTapRegionCalibrationProfileStore()
        let bridge = try RuntimeBridge(
            calibrationStore: tapStore,
            regionCalibrationStore: regionStore
        )
        let profile = TapRegionCalibrationProfile(
            version: "personal-region-bridge-test",
            lowerBoundary: -1,
            upperBoundary: 1,
            lowerSide: .left,
            samplesPerGesture: 5
        )

        try bridge.applyTapRegionCalibration(profile)

        XCTAssertEqual(
            bridge.currentTapRegionCalibrationProfile,
            profile
        )
        XCTAssertEqual(regionStore.load(), .loaded(profile))
        XCTAssertEqual(tapStore.load(), .missing)

        try bridge.resetTapRegionCalibration()
        XCTAssertNil(bridge.currentTapRegionCalibrationProfile)
        XCTAssertEqual(regionStore.load(), .missing)
        XCTAssertEqual(tapStore.load(), .missing)
    }

    func testPanelLifecycleUsesNotchSurfaceAdapter() async throws {
        let surface = FakeNotchSurface()
        let controller = PanelController(surface: surface)
        let screen = try XCTUnwrap(NSScreen.main)

        controller.setRootView(AnyView(Text("Panel")))
        controller.showInteractive(on: screen)
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(surface.setContentCount, 1)
        XCTAssertEqual(surface.expandedCount, 1)
        XCTAssertEqual(controller.mode, .interactive)

        controller.dismiss()
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(surface.hideCount, 1)
        XCTAssertEqual(controller.mode, .closed)
    }

    func testPassiveHintExpandsInOneSurfaceTransition() async throws {
        guard NSScreen.screens.contains(where: {
            $0.mactivateDescriptor?.isBuiltIn == true &&
                $0.mactivateDescriptor?.hasNotch == true
        }) else {
            throw XCTSkip("requires a built-in notched display")
        }
        let surface = FakeNotchSurface()
        let controller = PanelController(surface: surface)

        controller.showPassiveHint()
        for _ in 0..<6 {
            await Task.yield()
        }

        XCTAssertEqual(surface.compactCount, 0)
        XCTAssertEqual(surface.expandedCount, 1)
        XCTAssertEqual(controller.mode, .passiveHint)
        controller.dismiss()
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
        XCTAssertEqual(coordinator.state.tapStatus, "Sensor connected · 796 Hz")
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

    func testSpatialDecisionDiagnosticsIncludeSideFeatureAndModel() {
        let runtime = FakeRuntime()
        let coordinator = makeCoordinator(runtime: runtime)

        runtime.outputHandler?(.tapFeedback(TapFeedback(
            outcome: .spatialUnavailable(
                pattern: .double,
                reason: .ambiguous
            ),
            memberCount: 2,
            features: TapEventFeatures(
                time: 1,
                peakG: 0.1,
                decayMs: 20,
                zImpulseMgS: 0.1,
                lateralImpulseMgS: 0.1
            ),
            sensorTimestamp: 1,
            resolutionLatencyS: 1,
            regionPrediction: .unknown,
            regionMemberFeatures: [-1, 1],
            regionFeature: 0,
            regionProfileVersion: "personal-region-diagnostics",
            regionReason: .ambiguous
        )))

        XCTAssertTrue(coordinator.state.diagnosticText.contains("side=unknown"))
        XCTAssertTrue(coordinator.state.diagnosticText.contains("feature=0.00000"))
        XCTAssertTrue(
            coordinator.state.diagnosticText.contains(
                "model=personal-region-diagnostics"
            )
        )
        XCTAssertTrue(
            coordinator.state.tapFeedbackDescription.contains("guard band")
        )
    }

    func testUnknownActionIdentifierFailsClosedWithoutExecuting() {
        let runtime = FakeRuntime()
        let coordinator = makeCoordinator(runtime: runtime)
        let trigger = TapTrigger(
            eventID: RuntimeEventID(
                sessionID: UUID(),
                classifierEventID: "tap-1"
            ),
            gesture: .leftDouble,
            sensorTimestamp: 1,
            regionProfileVersion: "personal-region-test"
        )

        runtime.outputHandler?(.intent(.performAction(
            id: "action.does-not-exist",
            trigger: trigger
        )))

        XCTAssertNotNil(coordinator.state.actionError)
    }

    func testTapIntentForShowPanelExpandsNotchSurface() async {
        let runtime = FakeRuntime()
        let surface = FakeNotchSurface()
        let panelController = PanelController(surface: surface)
        let coordinator = makeCoordinator(
            runtime: runtime,
            panelController: panelController
        )
        let trigger = TapTrigger(
            eventID: RuntimeEventID(
                sessionID: UUID(),
                classifierEventID: "show-panel"
            ),
            gesture: .leftDouble,
            sensorTimestamp: 1,
            regionProfileVersion: "personal-region-test"
        )

        runtime.outputHandler?(.intent(.performAction(
            id: AppActionDefinition.showPanel.id,
            trigger: trigger
        )))
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(surface.expandedCount, 1)
        XCTAssertEqual(panelController.mode, .interactive)
        panelController.dismiss()
    }

    func testSetSpatialTapBindingUpdatesConfigurationOnSuccess() {
        let runtime = FakeRuntime()
        let coordinator = makeCoordinator(runtime: runtime)

        coordinator.setSpatialTapBinding(
            "builtin.show-panel",
            gesture: .leftDouble
        )

        XCTAssertEqual(
            coordinator.state.configuration.spatialTapBindings.leftDouble,
            "builtin.show-panel"
        )
        XCTAssertNil(coordinator.state.recentWarning)
    }

    func testPanelAssignmentsExcludeShowPanelButGesturesKeepIt() {
        let coordinator = makeCoordinator(runtime: FakeRuntime())
        XCTAssertTrue(
            coordinator.addWebURL(
                name: "Example",
                value: "https://example.com"
            )
        )

        XCTAssertTrue(coordinator.state.actions.contains(
            AppActionDefinition.showPanel
        ))
        XCTAssertFalse(coordinator.state.panelAssignableActions.contains(
            AppActionDefinition.showPanel
        ))
        XCTAssertEqual(coordinator.state.panelAssignableActions.count, 1)
    }

    func testSetSpatialTapBindingSurfacesRuntimeFailureAsWarning() {
        let runtime = FakeRuntime()
        runtime.setSpatialTapBindingError = TestFailure("rejected")
        let coordinator = makeCoordinator(runtime: runtime)

        coordinator.setSpatialTapBinding(
            "builtin.show-panel",
            gesture: .rightTriple
        )

        XCTAssertEqual(coordinator.state.recentWarning, "rejected")
    }

    func testTapCalibrationRetriesRejectedSamplesAndStopsAtFive() {
        let runtime = FakeRuntime()
        let coordinator = makeCoordinator(runtime: runtime)
        let target = TapCalibrationTarget(side: .left, intensity: .comfort)
        coordinator.state.tapCalibrationTarget = target

        runtime.outputHandler?(.tapFeedback(calibrationFeedback(
            outcome: .rejected(.comfortZImpulse),
            zImpulseMgS: -0.2
        )))

        XCTAssertEqual(
            coordinator.state.tapCalibrationDraft.sampleCount(
                side: .left,
                intensity: .comfort
            ),
            0
        )
        XCTAssertNotNil(coordinator.state.tapCalibrationError)

        for _ in 0..<TapCalibrationDraft.requiredSamplesPerTarget {
            runtime.outputHandler?(.tapFeedback(calibrationFeedback(
                outcome: .acceptedNonActionable(.single),
                zImpulseMgS: 0.2
            )))
        }

        XCTAssertEqual(
            coordinator.state.tapCalibrationDraft.sampleCount(
                side: .left,
                intensity: .comfort
            ),
            TapCalibrationDraft.requiredSamplesPerTarget
        )
        XCTAssertNil(coordinator.state.tapCalibrationTarget)
        XCTAssertNil(coordinator.state.tapCalibrationError)
    }

    func testRegionCalibrationAdvancesTargetsAndSavesQualifiedProfile() {
        let runtime = FakeRuntime()
        let coordinator = makeCoordinator(runtime: runtime)
        coordinator.state.tapRegionCalibrationTarget =
            TapRegionCalibrationTarget.ordered.first

        for index in 0..<20 {
            guard let target =
                    coordinator.state.tapRegionCalibrationTarget else {
                return XCTFail("calibration ended before 20 gestures")
            }
            let base = target.side == .left ? -3.0 : 3.0
            let memberFeatures = (0..<target.pattern.memberCount).map {
                base + Double(index % 5) * 0.01 + Double($0) * 0.02
            }
            runtime.outputHandler?(.tapFeedback(TapFeedback(
                outcome: index == 19
                    ? .dispatched(
                        gesture: PalmTapGesture(
                            side: target.side,
                            pattern: target.pattern
                        ),
                        action: "calibration.action"
                    )
                    : .spatialUnavailable(
                        pattern: target.pattern,
                        reason: .calibrationRequired
                    ),
                memberCount: target.pattern.memberCount,
                features: TapEventFeatures(
                    time: Double(index),
                    peakG: 0.1,
                    decayMs: 20,
                    zImpulseMgS: 0.1,
                    lateralImpulseMgS: 0.1
                ),
                sensorTimestamp: Double(index),
                resolutionLatencyS: 1,
                regionPrediction: .unknown,
                regionMemberFeatures: memberFeatures,
                regionFeature: memberFeatures.reduce(0, +) /
                    Double(memberFeatures.count),
                regionReason: .ambiguous
            )))
        }
        runtime.outputHandler?(.intent(.performAction(
            id: "calibration.action",
            trigger: TapTrigger(
                eventID: RuntimeEventID(
                    sessionID: UUID(),
                    classifierEventID: "final-calibration-gesture"
                ),
                gesture: .rightTriple,
                sensorTimestamp: 20,
                regionProfileVersion: "personal-region-old"
            )
        )))

        XCTAssertNil(coordinator.state.tapRegionCalibrationTarget)
        XCTAssertTrue(
            coordinator.state.tapRegionCalibrationProfile?.isValid == true
        )
        XCTAssertEqual(
            runtime.currentTapRegionCalibrationProfile,
            coordinator.state.tapRegionCalibrationProfile
        )
        XCTAssertNil(coordinator.state.actionError)
    }

    func testSetQuickActionPersistsIntoNormalizedSlot() {
        let runtime = FakeRuntime()
        let coordinator = makeCoordinator(runtime: runtime)
        XCTAssertTrue(
            coordinator.addWebURL(
                name: "Example",
                value: "https://example.com"
            )
        )
        let identifier = coordinator.state.preferences.actions[0].id

        coordinator.setQuickAction(index: 1, identifier: identifier)

        XCTAssertEqual(
            coordinator.state.preferences.normalizedQuickActionIDs[1],
            identifier
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
        coordinator.setSpatialTapBinding(action.id, gesture: .rightDouble)

        coordinator.deleteAction(action.id)

        XCTAssertTrue(coordinator.state.preferences.actions.isEmpty)
        XCTAssertTrue(
            coordinator.state.preferences.normalizedQuickActionIDs
                .allSatisfy { $0 == nil }
        )
        XCTAssertNil(
            coordinator.state.configuration.spatialTapBindings.rightDouble
        )
    }

    func testResetSettingsRestoresRuntimeAndAppDefaults() {
        let runtime = FakeRuntime()
        let coordinator = makeCoordinator(runtime: runtime)
        coordinator.addShortcut(name: "Focus")
        coordinator.setSpatialTapBinding(
            "builtin.show-panel",
            gesture: .leftTriple
        )

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
        launchAtLogin: TestLaunchAtLogin = TestLaunchAtLogin(),
        panelController: PanelController? = nil
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
            launchAtLogin: launchAtLogin,
            panelController: panelController
        )
    }

    private func calibrationFeedback(
        outcome: TapFeedbackOutcome,
        zImpulseMgS: Double
    ) -> TapFeedback {
        let verdict: TapVerdict =
            if case .rejected = outcome {
                .rejected
            } else {
                .acceptedComfort
            }
        return TapFeedback(
            outcome: outcome,
            acceptanceVerdict: verdict,
            memberCount: 1,
            features: TapEventFeatures(
                time: 1,
                peakG: 0.1,
                decayMs: 20,
                zImpulseMgS: zImpulseMgS,
                lateralImpulseMgS: 0.1
            ),
            sensorTimestamp: 1,
            resolutionLatencyS: 0.6
        )
    }
}

@MainActor
private final class FakeNotchSurface: NotchSurfaceControlling {
    var window: NSWindow?
    private(set) var setContentCount = 0
    private(set) var compactCount = 0
    private(set) var expandedCount = 0
    private(set) var hideCount = 0

    func setContent(_ content: AnyView) {
        setContentCount += 1
    }

    func showCompact(on screen: NSScreen) async {
        compactCount += 1
    }

    func showExpanded(on screen: NSScreen, interactive: Bool) async {
        expandedCount += 1
    }

    func hide() async {
        hideCount += 1
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
    var currentTapCalibrationProfile: RuntimeTapCalibrationProfile?
    var currentTapRegionCalibrationProfile:
        RuntimeTapRegionCalibrationProfile?
    var tapCalibrationWarning: String?
    var tapRegionCalibrationWarning: String?
    private(set) var configurationReadCount = 0
    var startCount = 0
    var stopCount = 0
    var setSpatialTapBindingError: Error?

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

    func setSpatialTapBinding(
        _ action: ActionIdentifier?,
        for gesture: PalmTapGesture
    ) throws {
        if let setSpatialTapBindingError {
            throw setSpatialTapBindingError
        }
        configuration.spatialTapBindings[gesture] = action
    }

    func setPanelHintsEnabled(_ enabled: Bool) throws {
        configuration.panelHintsEnabled = enabled
    }

    func resetConfiguration() throws {
        configuration = .default
    }

    func applyTapCalibration(_ profile: RuntimeTapCalibrationProfile) throws {
        currentTapCalibrationProfile = profile
    }

    func resetTapCalibration() throws {
        currentTapCalibrationProfile = nil
    }

    func applyTapRegionCalibration(
        _ profile: RuntimeTapRegionCalibrationProfile
    ) throws {
        currentTapRegionCalibrationProfile = profile
    }

    func resetTapRegionCalibration() throws {
        currentTapRegionCalibrationProfile = nil
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
