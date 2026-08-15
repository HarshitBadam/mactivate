import Foundation
import XCTest
@testable import MactivateApp

final class AppPreferencesStoreTests: XCTestCase {
    func testPreferencesRoundTrip() throws {
        let (defaults, key) = makeDefaults()
        let store = UserDefaultsAppPreferencesStore(
            defaults: defaults,
            key: key
        )
        let action = AppActionDefinition.shortcut(name: "Focus")
        let preferences = AppPreferences(
            actions: [action],
            quickActionIDs: [action.id],
            onboardingCompleted: true
        )

        try store.save(preferences)

        XCTAssertEqual(store.load().preferences, preferences)
        XCTAssertNil(store.load().warning)
    }

    func testCorruptPreferencesFailClosedWithWarning() {
        let (defaults, key) = makeDefaults()
        defaults.set(Data("{bad-json".utf8), forKey: key)
        let store = UserDefaultsAppPreferencesStore(
            defaults: defaults,
            key: key
        )

        let result = store.load()

        XCTAssertEqual(result.preferences, .default)
        XCTAssertNotNil(result.warning)
    }

    func testFuturePreferencesFailClosedWithoutOverwritingData() {
        let (defaults, key) = makeDefaults()
        let future = Data(
            """
            {"schemaVersion":3,"actions":[],"quickActionIDs":[],
             "onboardingCompleted":true}
            """.utf8
        )
        defaults.set(future, forKey: key)
        let store = UserDefaultsAppPreferencesStore(
            defaults: defaults,
            key: key
        )

        let result = store.load()

        XCTAssertEqual(result.preferences, .default)
        XCTAssertNotNil(result.warning)
        XCTAssertEqual(defaults.data(forKey: key), future)
    }

    func testInvalidWebSchemeCannotBeSaved() {
        let action = AppActionDefinition(
            id: "action.invalid",
            name: "Unsafe",
            kind: .webURL("file:///tmp/test")
        )
        let preferences = AppPreferences(actions: [action])
        let store = InMemoryAppPreferencesStore()

        XCTAssertThrowsError(try store.save(preferences))
    }

    func testQuickActionsAreNormalizedToFourSlots() {
        let action = AppActionDefinition.shortcut(name: "Focus")
        let preferences = AppPreferences(
            actions: [action],
            quickActionIDs: [action.id]
        )

        XCTAssertEqual(preferences.normalizedQuickActionIDs.count, 4)
        XCTAssertEqual(preferences.normalizedQuickActionIDs.first!, action.id)
    }

    func testMoreThanFourPersistedSlotsAreRejected() {
        let action = AppActionDefinition.shortcut(name: "Focus")
        let preferences = AppPreferences(
            actions: [action],
            quickActionIDs: Array(repeating: action.id, count: 5)
        )

        XCTAssertFalse(preferences.isValid)
    }

    func testCustomActionCannotCollideWithBuiltInShowPanel() {
        let collision = AppActionDefinition(
            id: AppActionDefinition.showPanel.id,
            name: "Pretend action",
            kind: .shortcut(name: "Focus")
        )

        XCTAssertFalse(AppPreferences(actions: [collision]).isValid)
    }

    func testVersionOneMigrationPreservesActionsAndClearsCircularPanelSlot() throws {
        let (defaults, key) = makeDefaults()
        let action = AppActionDefinition.shortcut(name: "Focus")
        let legacy = AppPreferences(
            schemaVersion: 1,
            actions: [action],
            quickActionIDs: [AppActionDefinition.showPanel.id, action.id],
            onboardingCompleted: true
        )
        defaults.set(try JSONEncoder().encode(legacy), forKey: key)
        let store = UserDefaultsAppPreferencesStore(
            defaults: defaults,
            key: key
        )

        let result = store.load()

        XCTAssertNil(result.warning)
        XCTAssertEqual(result.preferences.schemaVersion, 2)
        XCTAssertEqual(result.preferences.actions, [action])
        XCTAssertNil(result.preferences.normalizedQuickActionIDs[0])
        XCTAssertEqual(
            result.preferences.normalizedQuickActionIDs[1],
            action.id
        )
        XCTAssertTrue(result.preferences.onboardingCompleted)
    }

    func testPendingLoginApprovalStillCountsAsRegistered() {
        XCTAssertTrue(LaunchAtLoginStatus.requiresApproval.isRegistered)
        XCTAssertTrue(LaunchAtLoginStatus.enabled.isRegistered)
        XCTAssertFalse(LaunchAtLoginStatus.disabled.isRegistered)
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suite = "MactivateAppTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (defaults, "preferences")
    }
}
