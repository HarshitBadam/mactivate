import MactivateRuntime
import XCTest
@testable import MactivateApp

@MainActor
final class SpatialTapBindingTests: XCTestCase {
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

    func testSetSpatialTapDispatchEnabledUpdatesConfiguration() {
        let runtime = FakeRuntime()
        let coordinator = makeCoordinator(runtime: runtime)

        coordinator.setSpatialTapDispatchEnabled(false)

        XCTAssertFalse(
            coordinator.state.configuration.spatialTapDispatchEnabled
        )
        XCTAssertNil(coordinator.state.recentWarning)
    }

    func testSetSpatialTapDispatchEnabledSurfacesRuntimeFailure() {
        let runtime = FakeRuntime()
        runtime.setSpatialTapDispatchEnabledError = TestFailure("rejected")
        let coordinator = makeCoordinator(runtime: runtime)

        coordinator.setSpatialTapDispatchEnabled(false)

        XCTAssertTrue(
            coordinator.state.configuration.spatialTapDispatchEnabled
        )
        XCTAssertEqual(coordinator.state.recentWarning, "rejected")
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
}
