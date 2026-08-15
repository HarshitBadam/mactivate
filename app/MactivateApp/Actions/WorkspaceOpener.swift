import AppKit
import Foundation

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
