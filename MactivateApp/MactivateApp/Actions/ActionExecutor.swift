import AppKit
import Foundation
import MactivateRuntime

protocol WorkspaceOpening {
    func openApplication(bundleIdentifier: String,
                         completion: @escaping (Result<Void, Error>) -> Void)
    func openURL(_ url: URL,
                 completion: @escaping (Result<Void, Error>) -> Void)
}

final class SystemWorkspaceOpener: WorkspaceOpening {
    private let workspace: NSWorkspace
    private let queue = DispatchQueue(
        label: "com.mactivate.actions.workspace",
        qos: .userInitiated
    )

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    func openApplication(bundleIdentifier: String,
                         completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async { [workspace] in
            guard let url = workspace.urlForApplication(
                withBundleIdentifier: bundleIdentifier
            ) else {
                DispatchQueue.main.async {
                    completion(.failure(
                        AppActionError.applicationUnavailable(bundleIdentifier)
                    ))
                }
                return
            }
            let configuration = NSWorkspace.OpenConfiguration()
            workspace.openApplication(
                at: url,
                configuration: configuration
            ) { _, error in
                DispatchQueue.main.async {
                    if let error {
                        completion(.failure(error))
                    } else {
                        completion(.success(()))
                    }
                }
            }
        }
    }

    func openURL(_ url: URL,
                 completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async { [workspace] in
            let opened = workspace.open(url)
            DispatchQueue.main.async {
                completion(opened ? .success(()) : .failure(AppActionError.invalidURL))
            }
        }
    }
}

protocol ShortcutRunning {
    func run(name: String,
             completion: @escaping (Result<Void, Error>) -> Void)
    func list(completion: @escaping (Result<[String], Error>) -> Void)
}

final class SystemShortcutRunner: ShortcutRunning {
    private let queue = DispatchQueue(
        label: "com.mactivate.actions.shortcuts",
        qos: .userInitiated,
        attributes: .concurrent
    )

    func run(name: String,
             completion: @escaping (Result<Void, Error>) -> Void) {
        execute(arguments: ["run", name]) { result in
            completion(result.map { _ in () })
        }
    }

    func list(completion: @escaping (Result<[String], Error>) -> Void) {
        execute(arguments: ["list"]) { result in
            completion(result.map { output in
                output.split(whereSeparator: \.isNewline)
                    .map(String.init)
                    .filter { !$0.isEmpty }
                    .sorted()
            })
        }
    }

    private func execute(
        arguments: [String],
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        queue.async {
            let process = Process()
            let outputPipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = arguments
            process.standardOutput = outputPipe
            process.standardError = outputPipe
            do {
                try process.run()
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let output = String(data: outputData, encoding: .utf8) ?? ""
                DispatchQueue.main.async {
                    if process.terminationStatus == 0 {
                        completion(.success(output))
                    } else {
                        let reason = output.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                        completion(.failure(AppActionError.shortcutFailed(
                            reason.isEmpty ? "exit \(process.terminationStatus)" : reason
                        )))
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
}

final class ActionExecutor {
    enum Outcome {
        case executed
        case skippedDuplicate
    }

    private let workspace: WorkspaceOpening
    private let shortcuts: ShortcutRunning
    private let lock = NSLock()
    private var tapIDs: Set<RuntimeEventID> = []
    private var tapIDOrder: [RuntimeEventID] = []
    private let tapIDLimit: Int

    init(workspace: WorkspaceOpening = SystemWorkspaceOpener(),
         shortcuts: ShortcutRunning = SystemShortcutRunner(),
         tapIDLimit: Int = 256) {
        precondition(tapIDLimit > 0)
        self.workspace = workspace
        self.shortcuts = shortcuts
        self.tapIDLimit = tapIDLimit
    }

    func execute(_ action: AppActionDefinition,
                 invocation: ActionInvocation,
                 completion: @escaping (Result<Outcome, Error>) -> Void) {
        if case .tap(let trigger) = invocation,
           !reserve(trigger.eventID) {
            completion(.success(.skippedDuplicate))
            return
        }

        switch action.kind {
        case .showPanel:
            completion(.success(.executed))
        case .application(let bundleIdentifier):
            workspace.openApplication(
                bundleIdentifier: bundleIdentifier
            ) { result in
                completion(result.map { .executed })
            }
        case .webURL(let value):
            guard let url = URL(string: value),
                  let scheme = url.scheme?.lowercased(),
                  ["http", "https"].contains(scheme),
                  url.host != nil else {
                completion(.failure(AppActionError.invalidURL))
                return
            }
            workspace.openURL(url) { result in
                completion(result.map { .executed })
            }
        case .shortcut(let name):
            shortcuts.run(name: name) { result in
                completion(result.map { .executed })
            }
        }
    }

    func listShortcuts(
        completion: @escaping (Result<[String], Error>) -> Void
    ) {
        shortcuts.list(completion: completion)
    }

    private func reserve(_ id: RuntimeEventID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard tapIDs.insert(id).inserted else { return false }
        tapIDOrder.append(id)
        if tapIDOrder.count > tapIDLimit {
            let removed = tapIDOrder.removeFirst()
            tapIDs.remove(removed)
        }
        return true
    }
}
