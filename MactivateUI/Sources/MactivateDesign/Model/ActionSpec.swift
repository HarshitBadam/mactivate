import Foundation

/// What an action does. Kept as a `String`-backed kind plus a parameter bag
/// rather than an enum with associated values, because the product vision
/// explicitly refuses to freeze the action model yet: a new kind is a new case
/// plus a descriptor, and configurations written by an older build still decode.
public enum ActionKind: String, Codable, CaseIterable, Sendable {
    case openURL
    case openApp
    case screenshot
    case runShortcut
    case runShellCommand
    case keystroke
    case systemCommand
    /// A kind this build does not understand, preserved verbatim so a newer
    /// build's configuration survives a round trip through an older one.
    case unrecognized
}

/// Which macOS permission an action needs. Surfaced in the UI *before* the user
/// binds the action, so a binding never silently does nothing.
public enum ActionPermission: String, Codable, CaseIterable, Sendable {
    case none
    case accessibility
    case screenRecording
    case automation

    public var displayName: String {
        switch self {
        case .none: return "No permission required"
        case .accessibility: return "Accessibility"
        case .screenRecording: return "Screen Recording"
        case .automation: return "Automation"
        }
    }
}

/// Static description of an action kind: how to name it, draw it, explain it,
/// and which parameters it needs. One table drives the action picker, the
/// binding rows, the macro pad, and validation.
public struct ActionKindDescriptor: Sendable {
    public var kind: ActionKind
    public var displayName: String
    public var symbolName: String
    public var summary: String
    public var permission: ActionPermission
    /// Parameter keys that must be present and non-empty.
    public var requiredParameters: [String]
    /// True when running the action can change files or system state, which is
    /// what makes the UI ask for confirmation before a first run.
    public var isConsequential: Bool

    public init(
        kind: ActionKind,
        displayName: String,
        symbolName: String,
        summary: String,
        permission: ActionPermission,
        requiredParameters: [String],
        isConsequential: Bool
    ) {
        self.kind = kind
        self.displayName = displayName
        self.symbolName = symbolName
        self.summary = summary
        self.permission = permission
        self.requiredParameters = requiredParameters
        self.isConsequential = isConsequential
    }
}

public enum ActionParameterKey {
    public static let url = "url"
    public static let bundleIdentifier = "bundleIdentifier"
    public static let shortcutName = "shortcutName"
    public static let command = "command"
    public static let keys = "keys"
    public static let scope = "scope"
    public static let systemCommandID = "commandID"
}

/// A configured action: a kind, its parameters, and the user's label for it.
public struct ActionSpec: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var kind: ActionKind
    /// Preserved when `kind == .unrecognized` so unknown actions round-trip.
    public var rawKind: String?
    public var parameters: [String: String]
    /// User-facing name. Empty means "derive it from the parameters", which is
    /// what keeps the picker from demanding a name for `Open github.com`.
    public var customName: String?
    /// Optional SF Symbol override, mainly for macro-pad buttons.
    public var customSymbolName: String?

    public init(
        id: UUID = UUID(),
        kind: ActionKind,
        rawKind: String? = nil,
        parameters: [String: String] = [:],
        customName: String? = nil,
        customSymbolName: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.rawKind = rawKind
        self.parameters = parameters
        self.customName = customName
        self.customSymbolName = customSymbolName
    }

    public var descriptor: ActionKindDescriptor { ActionCatalog.descriptor(for: kind) }

    public var symbolName: String { customSymbolName ?? descriptor.symbolName }

    /// One line naming the action: the user's own label when they set one,
    /// otherwise a derived phrase that reads like a sentence fragment
    /// ("Open github.com", "Run Shortcut “Focus”").
    public var title: String {
        if let customName, !customName.trimmingCharacters(in: .whitespaces).isEmpty {
            return customName
        }
        return derivedTitle
    }

    private var derivedTitle: String {
        switch kind {
        case .openURL:
            let raw = parameters[ActionParameterKey.url] ?? ""
            return raw.isEmpty ? "Open URL" : "Open \(ActionSpec.displayHost(for: raw))"
        case .openApp:
            let bundle = parameters[ActionParameterKey.bundleIdentifier] ?? ""
            let leaf = bundle.split(separator: ".").last.map(String.init) ?? ""
            return leaf.isEmpty ? "Open App" : "Open \(leaf)"
        case .screenshot:
            let scope = parameters[ActionParameterKey.scope] ?? "selection"
            return "Screenshot (\(scope))"
        case .runShortcut:
            let name = parameters[ActionParameterKey.shortcutName] ?? ""
            return name.isEmpty ? "Run Shortcut" : "Run Shortcut “\(name)”"
        case .runShellCommand:
            let command = parameters[ActionParameterKey.command] ?? ""
            return command.isEmpty ? "Run Command" : "Run “\(ActionSpec.truncate(command, to: 28))”"
        case .keystroke:
            let keys = parameters[ActionParameterKey.keys] ?? ""
            return keys.isEmpty ? "Send Keystroke" : "Send \(keys)"
        case .systemCommand:
            let identifier = parameters[ActionParameterKey.systemCommandID] ?? ""
            return identifier.isEmpty ? "System Command" : identifier.replacingOccurrences(of: "_", with: " ").capitalized
        case .unrecognized:
            return rawKind.map { "Unsupported action (\($0))" } ?? "Unsupported action"
        }
    }

    /// Secondary line for detail rows: the concrete target, so the user can tell
    /// two `Open URL` bindings apart without opening the editor.
    public var detail: String? {
        switch kind {
        case .openURL: return parameters[ActionParameterKey.url]
        case .openApp: return parameters[ActionParameterKey.bundleIdentifier]
        case .runShortcut: return parameters[ActionParameterKey.shortcutName]
        case .runShellCommand: return parameters[ActionParameterKey.command]
        case .keystroke: return parameters[ActionParameterKey.keys]
        case .screenshot, .systemCommand: return nil
        case .unrecognized: return rawKind
        }
    }

    /// Missing or empty required parameters. A non-empty result is what makes
    /// the editor's Save button unavailable and marks the binding incomplete.
    public var missingParameters: [String] {
        descriptor.requiredParameters.filter { key in
            (parameters[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "").isEmpty
        }
    }

    public var isRunnable: Bool { kind != .unrecognized && missingParameters.isEmpty }

    static func displayHost(for raw: String) -> String {
        guard let components = URLComponents(string: raw), let host = components.host else {
            return truncate(raw, to: 28)
        }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    static func truncate(_ text: String, to limit: Int) -> String {
        text.count <= limit ? text : String(text.prefix(limit - 1)) + "…"
    }
}

extension ActionSpec {
    private enum CodingKeys: String, CodingKey {
        case id, kind, rawKind, parameters, customName, customSymbolName
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        let storedKind = try container.decode(String.self, forKey: .kind)
        if let known = ActionKind(rawValue: storedKind), known != .unrecognized {
            kind = known
            rawKind = try container.decodeIfPresent(String.self, forKey: .rawKind)
        } else {
            kind = .unrecognized
            rawKind = storedKind
        }
        parameters = try container.decodeIfPresent([String: String].self, forKey: .parameters) ?? [:]
        customName = try container.decodeIfPresent(String.self, forKey: .customName)
        customSymbolName = try container.decodeIfPresent(String.self, forKey: .customSymbolName)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind == .unrecognized ? (rawKind ?? kind.rawValue) : kind.rawValue, forKey: .kind)
        if kind != .unrecognized { try container.encodeIfPresent(rawKind, forKey: .rawKind) }
        try container.encode(parameters, forKey: .parameters)
        try container.encodeIfPresent(customName, forKey: .customName)
        try container.encodeIfPresent(customSymbolName, forKey: .customSymbolName)
    }
}

/// The action kinds this build offers, their descriptors, and a few presets used
/// to make an empty configuration feel considered rather than blank.
public enum ActionCatalog {
    public static let descriptors: [ActionKindDescriptor] = [
        ActionKindDescriptor(
            kind: .openURL,
            displayName: "Open URL",
            symbolName: "safari",
            summary: "Opens a link in your default browser.",
            permission: .none,
            requiredParameters: [ActionParameterKey.url],
            isConsequential: false
        ),
        ActionKindDescriptor(
            kind: .openApp,
            displayName: "Open App",
            symbolName: "app.badge",
            summary: "Launches or activates an app.",
            permission: .none,
            requiredParameters: [ActionParameterKey.bundleIdentifier],
            isConsequential: false
        ),
        ActionKindDescriptor(
            kind: .screenshot,
            displayName: "Take Screenshot",
            symbolName: "camera.viewfinder",
            summary: "Captures the screen, a window, or a selection.",
            permission: .screenRecording,
            requiredParameters: [],
            isConsequential: false
        ),
        ActionKindDescriptor(
            kind: .runShortcut,
            displayName: "Run Shortcut",
            symbolName: "square.stack.3d.down.right",
            summary: "Runs a shortcut from the Shortcuts app.",
            permission: .none,
            requiredParameters: [ActionParameterKey.shortcutName],
            isConsequential: true
        ),
        ActionKindDescriptor(
            kind: .runShellCommand,
            displayName: "Run Shell Command",
            symbolName: "terminal",
            summary: "Runs a command with your shell environment.",
            permission: .none,
            requiredParameters: [ActionParameterKey.command],
            isConsequential: true
        ),
        ActionKindDescriptor(
            kind: .keystroke,
            displayName: "Send Keystroke",
            symbolName: "keyboard",
            summary: "Sends a key combination to the frontmost app.",
            permission: .accessibility,
            requiredParameters: [ActionParameterKey.keys],
            isConsequential: true
        ),
        ActionKindDescriptor(
            kind: .systemCommand,
            displayName: "System Command",
            symbolName: "switch.2",
            summary: "Runs a built-in command such as Mission Control or Do Not Disturb.",
            permission: .accessibility,
            requiredParameters: [ActionParameterKey.systemCommandID],
            isConsequential: false
        )
    ]

    static let unrecognizedDescriptor = ActionKindDescriptor(
        kind: .unrecognized,
        displayName: "Unsupported Action",
        symbolName: "questionmark.square.dashed",
        summary: "This action was created by a newer version of Mactivate. It is kept exactly as saved and will not run here.",
        permission: .none,
        requiredParameters: [],
        isConsequential: false
    )

    public static func descriptor(for kind: ActionKind) -> ActionKindDescriptor {
        descriptors.first { $0.kind == kind } ?? unrecognizedDescriptor
    }

    public static func openURL(_ url: String, name: String? = nil, symbol: String? = nil) -> ActionSpec {
        ActionSpec(
            kind: .openURL,
            parameters: [ActionParameterKey.url: url],
            customName: name,
            customSymbolName: symbol
        )
    }

    public static func screenshot(scope: String = "selection") -> ActionSpec {
        ActionSpec(kind: .screenshot, parameters: [ActionParameterKey.scope: scope])
    }

    public static func shortcut(_ name: String, symbol: String? = nil) -> ActionSpec {
        ActionSpec(
            kind: .runShortcut,
            parameters: [ActionParameterKey.shortcutName: name],
            customSymbolName: symbol
        )
    }

    public static func shell(_ command: String, name: String? = nil, symbol: String? = nil) -> ActionSpec {
        ActionSpec(
            kind: .runShellCommand,
            parameters: [ActionParameterKey.command: command],
            customName: name,
            customSymbolName: symbol
        )
    }

    public static func keystroke(_ keys: String, name: String? = nil, symbol: String? = nil) -> ActionSpec {
        ActionSpec(
            kind: .keystroke,
            parameters: [ActionParameterKey.keys: keys],
            customName: name,
            customSymbolName: symbol
        )
    }
}
