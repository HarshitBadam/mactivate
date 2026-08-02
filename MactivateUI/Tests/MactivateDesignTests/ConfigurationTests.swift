import XCTest
@testable import MactivateDesign

final class ConfigurationTests: XCTestCase {
    func testAFreshConfigurationBindsNothing() {
        let configuration = DefaultConfiguration.empty()
        XCTAssertEqual(configuration.boundCount, 0)
        XCTAssertTrue(configuration.macroPad.isEmpty)
        XCTAssertTrue(
            configuration.regions.allSatisfy { $0.calibration == .uncalibrated },
            "Defaults must never present a region as calibrated."
        )
        XCTAssertTrue(ConfigurationValidator.issues(in: configuration).isEmpty)
    }

    func testEveryRegionAlwaysOffersExactlyThreeBindings() {
        let configuration = PreviewFixtures.configuration()
        for region in configuration.regions {
            let bindings = configuration.bindings(for: region.id)
            XCTAssertEqual(bindings.count, 3)
            XCTAssertEqual(bindings.map(\.count), TapCount.allCases)
        }
    }

    func testRoundTripPreservesBindingsAndPad() throws {
        let original = PreviewFixtures.configuration()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(
            MactivateConfiguration.self,
            from: try encoder.encode(original)
        )

        XCTAssertEqual(decoded.bindings, original.bindings)
        XCTAssertEqual(decoded.macroPad, original.macroPad)
        XCTAssertEqual(decoded.triggers, original.triggers)
        // Region identity, naming, geometry, and calibration verdict must survive.
        // Calibration timestamps are stored at ISO-8601 second resolution, so they
        // are compared as instants rather than bit-for-bit.
        XCTAssertEqual(decoded.regions.map(\.id), original.regions.map(\.id))
        XCTAssertEqual(decoded.regions.map(\.name), original.regions.map(\.name))
        XCTAssertEqual(decoded.regions.map(\.frame), original.regions.map(\.frame))
        XCTAssertEqual(decoded.regions.map(\.calibration.tone), original.regions.map(\.calibration.tone))
    }

    func testAnActionFromANewerBuildSurvivesARoundTripAndDoesNotRun() throws {
        let json = """
        {
          "id": "3F2504E0-4F89-11D3-9A0C-0305E82C3301",
          "kind": "teleport",
          "parameters": { "destination": "moon" }
        }
        """
        let decoded = try JSONDecoder().decode(ActionSpec.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.kind, .unrecognized)
        XCTAssertEqual(decoded.rawKind, "teleport")
        XCTAssertFalse(decoded.isRunnable)

        let reEncoded = try JSONEncoder().encode(decoded)
        let object = try JSONSerialization.jsonObject(with: reEncoded) as? [String: Any]
        XCTAssertEqual(object?["kind"] as? String, "teleport", "Unknown kinds must round-trip verbatim.")
        XCTAssertEqual((object?["parameters"] as? [String: String])?["destination"], "moon")
    }

    func testANewerSchemaIsBlockingAndOffersToRevealTheFile() {
        var configuration = PreviewFixtures.configuration()
        configuration.schemaVersion = MactivateConfiguration.currentSchemaVersion + 1

        let issues = ConfigurationValidator.issues(in: configuration)
        XCTAssertFalse(ConfigurationValidator.isUsable(configuration))
        XCTAssertEqual(issues.first(where: { $0.id == "schema.newer" })?.severity, .blocking)
        XCTAssertEqual(issues.first(where: { $0.id == "schema.newer" })?.suggestedFix, "Reveal Configuration File")
    }

    func testAnIncompleteActionIsAdvisoryAndNamesTheRegionAndTapCount() {
        var configuration = PreviewFixtures.configuration()
        let region = TapRegionID(surface: .palmRest, zone: .left)
        configuration.setAction(ActionSpec(kind: .openURL), region: region, count: .triple)

        let issues = ConfigurationValidator.issues(in: configuration)
        let issue = issues.first { $0.id.hasPrefix("action.incomplete") }
        XCTAssertEqual(issue?.severity, .advisory)
        XCTAssertTrue(ConfigurationValidator.isUsable(configuration))
        XCTAssertEqual(issue?.message.contains("Triple Tap"), true)
        XCTAssertEqual(issue?.message.contains("Left Palm Rest"), true)
    }

    func testAnOrphanedBindingIsReportedRatherThanDropped() {
        var configuration = PreviewFixtures.configuration()
        configuration.bindings.append(
            TapBinding(
                region: TapRegionID(rawValue: "palmRest.diagonal"),
                count: .single,
                action: ActionCatalog.screenshot()
            )
        )
        let issues = ConfigurationValidator.issues(in: configuration)
        XCTAssertTrue(issues.contains { $0.id.hasPrefix("binding.orphan") })
        XCTAssertTrue(
            configuration.bindings.contains { $0.region.rawValue == "palmRest.diagonal" },
            "Validation must report, never silently rewrite a binding."
        )
    }

    func testOutOfRangeTriggerSettingsBlockAndOfferAReset() {
        var configuration = PreviewFixtures.configuration()
        configuration.triggers.handNearSensitivity = 4
        configuration.triggers.autoDismissDelay = 0

        let issues = ConfigurationValidator.issues(in: configuration)
        XCTAssertEqual(issues.filter { $0.severity == .blocking }.count, 2)
        XCTAssertTrue(issues.allSatisfy { $0.severity != .blocking || $0.suggestedFix == "Reset to Default" })
    }

    func testActionTitlesReadAsSentencesWithoutAUserSuppliedName() {
        XCTAssertEqual(ActionCatalog.openURL("https://www.github.com/pulls").title, "Open github.com")
        XCTAssertEqual(ActionCatalog.shortcut("Start Focus").title, "Run Shortcut “Start Focus”")
        XCTAssertEqual(ActionCatalog.keystroke("⌘⌥Space").title, "Send ⌘⌥Space")
        XCTAssertEqual(ActionCatalog.openURL("https://github.com", name: "GitHub").title, "GitHub")
        XCTAssertEqual(ActionSpec(kind: .openURL).title, "Open URL")
    }

    func testEveryOfferedActionKindHasADescriptorAndAPermissionStated() {
        for kind in ActionKind.allCases where kind != .unrecognized {
            let descriptor = ActionCatalog.descriptor(for: kind)
            XCTAssertEqual(descriptor.kind, kind, "Missing descriptor for \(kind).")
            XCTAssertFalse(descriptor.displayName.isEmpty)
            XCTAssertFalse(descriptor.summary.isEmpty)
            XCTAssertFalse(descriptor.symbolName.isEmpty)
        }
    }

    func testMacroPadPagesAlwaysFillAWholeGrid() {
        let slots = MacroPad.normalizedSlots([MacroPadSlot(action: ActionCatalog.screenshot())])
        XCTAssertEqual(slots.count, MacroPad.slotsPerPage)
        XCTAssertEqual(slots.filter(\.isEmpty).count, MacroPad.slotsPerPage - 1)
        XCTAssertEqual(slots.first?.displayLabel, "Screenshot (selection)")
        XCTAssertEqual(slots.last?.displayLabel, "Add Action")
    }

    func testSavingIsAtomicAndReloadsIdentically() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = FileConfigurationStore(url: directory.appendingPathComponent("configuration.json"))
        let missing = try await store.load()
        XCTAssertEqual(missing.boundCount, 0, "A missing file must load defaults, not fail.")

        let configuration = PreviewFixtures.configuration()
        try await store.save(configuration)
        try await store.save(configuration)

        let reloaded = try await store.load()
        XCTAssertEqual(reloaded.bindings, configuration.bindings)
        XCTAssertEqual(reloaded.macroPad, configuration.macroPad)
    }

    func testAFileFromANewerSchemaIsRefusedWithAnExplanation() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let url = directory.appendingPathComponent("configuration.json")
        var configuration = PreviewFixtures.configuration()
        configuration.schemaVersion = 99
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(configuration).write(to: url)

        let store = FileConfigurationStore(url: url)
        do {
            _ = try await store.load()
            XCTFail("A newer schema must not be silently accepted.")
        } catch let error as ConfigurationStoreError {
            XCTAssertEqual(error, .incompatibleSchema(found: 99, supported: MactivateConfiguration.currentSchemaVersion))
        }
    }
}
