import Foundation
import MactivateRuntime

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
