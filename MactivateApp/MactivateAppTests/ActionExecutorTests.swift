import Foundation
import MactivateRuntime
import XCTest
@testable import MactivateApp

final class ActionExecutorTests: XCTestCase {
    func testApplicationActionUsesBundleIdentifier() {
        let workspace = FakeWorkspace()
        let executor = ActionExecutor(
            workspace: workspace,
            shortcuts: FakeShortcuts()
        )
        let action = AppActionDefinition.application(
            name: "Notes",
            bundleIdentifier: "com.apple.Notes"
        )
        let completion = expectation(description: "action completion")

        executor.execute(action, invocation: .quickAction) { result in
            if case .failure(let error) = result {
                XCTFail("Unexpected failure: \(error)")
            }
            completion.fulfill()
        }

        wait(for: [completion], timeout: 1)
        XCTAssertEqual(workspace.openedBundleIdentifiers, ["com.apple.Notes"])
    }

    func testWebActionRejectsNonWebScheme() {
        let executor = ActionExecutor(
            workspace: FakeWorkspace(),
            shortcuts: FakeShortcuts()
        )
        let action = AppActionDefinition(
            id: "action.bad",
            name: "Bad",
            kind: .webURL("file:///tmp/test")
        )
        let completion = expectation(description: "action completion")

        executor.execute(action, invocation: .quickAction) { result in
            if case .success = result {
                XCTFail("Expected the invalid URL to fail")
            }
            completion.fulfill()
        }

        wait(for: [completion], timeout: 1)
    }

    func testWebActionOpensValidatedHTTPURL() {
        let workspace = FakeWorkspace()
        let executor = ActionExecutor(
            workspace: workspace,
            shortcuts: FakeShortcuts()
        )
        let action = AppActionDefinition.webURL(
            name: "Example",
            url: URL(string: "https://example.com")!
        )
        let completion = expectation(description: "action completion")

        executor.execute(action, invocation: .quickAction) { result in
            if case .failure(let error) = result {
                XCTFail("Unexpected failure: \(error)")
            }
            completion.fulfill()
        }

        wait(for: [completion], timeout: 1)
        XCTAssertEqual(workspace.openedURLs, [URL(string: "https://example.com")!])
    }

    func testDuplicateTapIDStartsOnlyOneAction() {
        let shortcuts = FakeShortcuts()
        let executor = ActionExecutor(
            workspace: FakeWorkspace(),
            shortcuts: shortcuts
        )
        let action = AppActionDefinition.shortcut(name: "Focus")
        let trigger = TapTrigger(
            eventID: RuntimeEventID(
                sessionID: UUID(),
                classifierEventID: "tap-1"
            ),
            pattern: .single,
            sensorTimestamp: 1
        )
        var outcomes: [ActionExecutor.Outcome] = []

        executor.execute(action, invocation: .tap(trigger)) {
            if case .success(let outcome) = $0 { outcomes.append(outcome) }
        }
        executor.execute(action, invocation: .tap(trigger)) {
            if case .success(let outcome) = $0 { outcomes.append(outcome) }
        }

        XCTAssertEqual(shortcuts.runNames, ["Focus"])
        XCTAssertEqual(outcomes.count, 2)
        if case .executed = outcomes[0] {} else {
            XCTFail("First invocation should execute")
        }
        if case .skippedDuplicate = outcomes[1] {} else {
            XCTFail("Second invocation should be skipped")
        }
    }
}

private final class FakeWorkspace: WorkspaceOpening {
    var openedBundleIdentifiers: [String] = []
    var openedURLs: [URL] = []

    func openApplication(
        bundleIdentifier: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        openedBundleIdentifiers.append(bundleIdentifier)
        completion(.success(()))
    }

    func openURL(
        _ url: URL,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        openedURLs.append(url)
        completion(.success(()))
    }
}

private final class FakeShortcuts: ShortcutRunning {
    var runNames: [String] = []

    func run(
        name: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        runNames.append(name)
        completion(.success(()))
    }

    func list(
        completion: @escaping (Result<[String], Error>) -> Void
    ) {
        completion(.success(["Focus"]))
    }
}
