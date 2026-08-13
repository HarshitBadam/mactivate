import Foundation
import MactivateRuntime

enum AppActionKind: Codable, Equatable {
    case showPanel
    case application(bundleIdentifier: String)
    case webURL(String)
    case shortcut(name: String)

    var symbolName: String {
        switch self {
        case .showPanel:
            return "rectangle.topthird.inset.filled"
        case .application:
            return "app"
        case .webURL:
            return "safari"
        case .shortcut:
            return "square.stack.3d.up.fill"
        }
    }
}

struct AppActionDefinition: Codable, Equatable, Identifiable {
    let id: ActionIdentifier
    var name: String
    var kind: AppActionKind

    static let showPanel = AppActionDefinition(
        id: "builtin.show-panel",
        name: "Show Panel",
        kind: .showPanel
    )

    static func application(name: String,
                            bundleIdentifier: String) -> AppActionDefinition {
        AppActionDefinition(
            id: ActionIdentifier(rawValue: "action.\(UUID().uuidString.lowercased())"),
            name: name,
            kind: .application(bundleIdentifier: bundleIdentifier)
        )
    }

    static func webURL(name: String, url: URL) -> AppActionDefinition {
        AppActionDefinition(
            id: ActionIdentifier(rawValue: "action.\(UUID().uuidString.lowercased())"),
            name: name,
            kind: .webURL(url.absoluteString)
        )
    }

    static func shortcut(name: String) -> AppActionDefinition {
        AppActionDefinition(
            id: ActionIdentifier(rawValue: "action.\(UUID().uuidString.lowercased())"),
            name: name,
            kind: .shortcut(name: name)
        )
    }

    var isValid: Bool {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard id.isValid, !cleanName.isEmpty, cleanName.utf8.count <= 128 else {
            return false
        }
        switch kind {
        case .showPanel:
            return id == Self.showPanel.id
        case .application(let bundleIdentifier):
            let value = bundleIdentifier.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            return !value.isEmpty && value.utf8.count <= 256
        case .webURL(let value):
            guard value.utf8.count <= 2_048 else { return false }
            guard let url = URL(string: value),
                  let scheme = url.scheme?.lowercased(),
                  ["http", "https"].contains(scheme),
                  url.host != nil else {
                return false
            }
            return true
        case .shortcut(let name):
            let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return !value.isEmpty && value.utf8.count <= 256
        }
    }
}

enum ActionInvocation {
    case quickAction
    case tap(TapTrigger)
}

enum AppActionError: LocalizedError, Equatable {
    case unknownAction
    case applicationUnavailable(String)
    case invalidURL
    case shortcutFailed(String)

    var errorDescription: String? {
        switch self {
        case .unknownAction:
            return "That action no longer exists."
        case .applicationUnavailable(let name):
            return "\(name) is not installed."
        case .invalidURL:
            return "The saved web address is invalid."
        case .shortcutFailed(let reason):
            return "The Shortcut failed: \(reason)"
        }
    }
}
