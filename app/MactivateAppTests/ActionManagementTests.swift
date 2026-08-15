import MactivateRuntime
import XCTest
@testable import MactivateApp

@MainActor
final class ActionManagementTests: XCTestCase {
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
}
