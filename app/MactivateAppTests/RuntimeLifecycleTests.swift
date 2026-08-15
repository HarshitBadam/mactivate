import MactuationCore
import MactivateRuntime
import XCTest
@testable import MactivateApp

@MainActor
final class RuntimeLifecycleTests: XCTestCase {
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
        XCTAssertEqual(coordinator.state.tapStatus, "Sensor connected at 796 Hz")
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
}
