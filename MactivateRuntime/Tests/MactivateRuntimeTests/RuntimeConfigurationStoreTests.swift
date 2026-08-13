import Foundation
import XCTest
@testable import MactivateRuntime

final class RuntimeConfigurationStoreTests: XCTestCase {
    func testMissingConfigurationUsesDefaultsWithoutWriting() {
        let (defaults, key) = makeDefaults()
        let store = UserDefaultsRuntimeConfigurationStore(
            defaults: defaults,
            key: key
        )

        XCTAssertEqual(store.load(), .missing(defaults: .default))
        XCTAssertNil(defaults.data(forKey: key))
    }

    func testConfigurationRoundTripsAsOneJSONBlob() throws {
        let (defaults, key) = makeDefaults()
        let store = UserDefaultsRuntimeConfigurationStore(
            defaults: defaults,
            key: key
        )
        let configuration = RuntimeConfiguration(
            tapBindings: TapBindings(
                single: "action.single",
                double: "action.double",
                triple: "action.triple"
            ),
            panelHintsEnabled: false
        )

        try store.save(configuration)

        XCTAssertEqual(store.load(), .loaded(configuration))
        XCTAssertNotNil(defaults.data(forKey: key))
    }

    func testCorruptConfigurationIsPreservedAndFailsClosedUntilReplaced() throws {
        let (defaults, key) = makeDefaults()
        let corrupt = Data("{not-json".utf8)
        defaults.set(corrupt, forKey: key)
        let store = UserDefaultsRuntimeConfigurationStore(
            defaults: defaults,
            key: key
        )

        let result = store.load()

        XCTAssertEqual(result.configuration, .failClosed)
        XCTAssertNotNil(result.warning)
        XCTAssertEqual(defaults.data(forKey: key), corrupt)

        try store.save(.default)
        XCTAssertEqual(store.load(), .loaded(.default))
    }

    func testFutureConfigurationIsPreservedAndFailsClosedUntilReplaced() throws {
        let (defaults, key) = makeDefaults()
        let future = Data(
            """
            {"schemaVersion":2,"tapBindings":{},"panelHintsEnabled":true}
            """.utf8
        )
        defaults.set(future, forKey: key)
        let store = UserDefaultsRuntimeConfigurationStore(
            defaults: defaults,
            key: key
        )

        let result = store.load()

        XCTAssertEqual(result.configuration, .failClosed)
        XCTAssertNotNil(result.warning)
        XCTAssertEqual(defaults.data(forKey: key), future)

        try store.save(.default)
        XCTAssertEqual(store.load(), .loaded(.default))
    }

    func testInvalidActionIdentifierCannotBeSaved() {
        let store = InMemoryRuntimeConfigurationStore()
        let invalid = RuntimeConfiguration(
            tapBindings: TapBindings(single: ActionIdentifier(rawValue: "  "))
        )

        XCTAssertThrowsError(try store.save(invalid))
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suite = "MactivateRuntimeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (defaults, "configuration")
    }
}
