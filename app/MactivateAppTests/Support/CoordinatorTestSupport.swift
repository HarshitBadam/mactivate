import MactuationCore
import MactivateRuntime
import XCTest
@testable import MactivateApp

@MainActor
extension XCTestCase {
    func makeCoordinator(
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

    func calibrationFeedback(
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
