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
            spatialTapBindings: SpatialTapBindings(
                leftDouble: "action.left-double",
                leftTriple: "action.left-triple",
                rightDouble: "action.right-double",
                rightTriple: "action.right-triple"
            ),
            spatialTapDispatchEnabled: false,
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
            {"schemaVersion":4,"spatialTapBindings":{},"spatialTapDispatchEnabled":true,"panelHintsEnabled":true}
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
            spatialTapBindings: SpatialTapBindings(
                leftDouble: ActionIdentifier(rawValue: "  ")
            )
        )

        XCTAssertThrowsError(try store.save(invalid))
    }

    func testVersionOneMigrationPreservesPanelHintAndClearsAllTapBindings()
        throws {
        let (defaults, key) = makeDefaults()
        defaults.set(Data(
            """
            {
              "schemaVersion": 1,
              "tapBindings": {
                "single": "old.single",
                "double": "old.double",
                "triple": "old.triple"
              },
              "panelHintsEnabled": false
            }
            """.utf8
        ), forKey: key)
        let store = UserDefaultsRuntimeConfigurationStore(
            defaults: defaults,
            key: key
        )

        let result = store.load()

        guard case .loaded(let migrated) = result else {
            return XCTFail("version one should migrate")
        }
        XCTAssertEqual(migrated.schemaVersion, 3)
        XCTAssertTrue(migrated.spatialTapDispatchEnabled)
        XCTAssertFalse(migrated.panelHintsEnabled)
        XCTAssertTrue(migrated.spatialTapBindings.isEmpty)
        XCTAssertEqual(
            try JSONDecoder().decode(
                RuntimeConfiguration.self,
                from: XCTUnwrap(defaults.data(forKey: key))
            ),
            migrated
        )
    }

    func testVersionTwoMigrationPreservesBindingsAndEnablesDispatch() throws {
        let (defaults, key) = makeDefaults()
        defaults.set(Data(
            """
            {
              "schemaVersion": 2,
              "spatialTapBindings": {
                "leftDouble": "left.double",
                "rightTriple": "right.triple"
              },
              "panelHintsEnabled": false
            }
            """.utf8
        ), forKey: key)
        let store = UserDefaultsRuntimeConfigurationStore(
            defaults: defaults,
            key: key
        )

        let result = store.load()

        guard case .loaded(let migrated) = result else {
            return XCTFail("version two should migrate")
        }
        XCTAssertEqual(migrated.schemaVersion, 3)
        XCTAssertTrue(migrated.spatialTapDispatchEnabled)
        XCTAssertFalse(migrated.panelHintsEnabled)
        XCTAssertEqual(
            migrated.spatialTapBindings.leftDouble,
            "left.double"
        )
        XCTAssertEqual(
            migrated.spatialTapBindings.rightTriple,
            "right.triple"
        )
        XCTAssertEqual(
            try JSONDecoder().decode(
                RuntimeConfiguration.self,
                from: XCTUnwrap(defaults.data(forKey: key))
            ),
            migrated
        )
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suite = "MactivateRuntimeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (defaults, "configuration")
    }
}
