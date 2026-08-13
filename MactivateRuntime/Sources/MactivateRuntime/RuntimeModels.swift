import Foundation
import MactuationCore

public struct ActionIdentifier: RawRepresentable, Codable, Equatable, Hashable,
    Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }

    public var isValid: Bool {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.utf8.count <= 256
    }
}

public enum TapPattern: Int, Codable, CaseIterable, Sendable {
    case single = 1
    case double = 2
    case triple = 3
}

public struct TapBindings: Codable, Equatable, Sendable {
    public var single: ActionIdentifier?
    public var double: ActionIdentifier?
    public var triple: ActionIdentifier?

    public init(single: ActionIdentifier? = nil,
                double: ActionIdentifier? = nil,
                triple: ActionIdentifier? = nil) {
        self.single = single
        self.double = double
        self.triple = triple
    }

    public subscript(pattern: TapPattern) -> ActionIdentifier? {
        get {
            switch pattern {
            case .single: return single
            case .double: return double
            case .triple: return triple
            }
        }
        set {
            switch pattern {
            case .single: single = newValue
            case .double: double = newValue
            case .triple: triple = newValue
            }
        }
    }

    var isValid: Bool {
        [single, double, triple].compactMap { $0 }.allSatisfy(\.isValid)
    }
}

public struct RuntimeConfiguration: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var tapBindings: TapBindings
    public var panelHintsEnabled: Bool

    public init(schemaVersion: Int = currentSchemaVersion,
                tapBindings: TapBindings = TapBindings(),
                panelHintsEnabled: Bool = true) {
        self.schemaVersion = schemaVersion
        self.tapBindings = tapBindings
        self.panelHintsEnabled = panelHintsEnabled
    }

    public static let `default` = RuntimeConfiguration()

    public static let failClosed = RuntimeConfiguration(
        tapBindings: TapBindings(),
        panelHintsEnabled: false
    )

    var isCurrentAndValid: Bool {
        schemaVersion == Self.currentSchemaVersion && tapBindings.isValid
    }
}

public struct RuntimeEventID: Equatable, Hashable, Sendable {
    public let sessionID: UUID
    public let classifierEventID: String

    public init(sessionID: UUID, classifierEventID: String) {
        self.sessionID = sessionID
        self.classifierEventID = classifierEventID
    }
}

public struct TapTrigger: Equatable, Sendable {
    public let eventID: RuntimeEventID
    public let pattern: TapPattern
    public let sensorTimestamp: SensorTimestamp

    public init(eventID: RuntimeEventID, pattern: TapPattern,
                sensorTimestamp: SensorTimestamp) {
        self.eventID = eventID
        self.pattern = pattern
        self.sensorTimestamp = sensorTimestamp
    }
}

public enum PanelPresentationReason: Equatable, Sendable {
    case ambientLightHint
}

public enum RuntimeIntent: Equatable, Sendable {
    case performAction(id: ActionIdentifier, trigger: TapTrigger)
    case showPanel(reason: PanelPresentationReason, hint: PanelOpenHint)
}

public enum RuntimeLifecycleState: Equatable, Sendable {
    case stopped
    case starting
    case running
    case suspended
    case stopping
}

public enum TapFeatureState: Equatable, Sendable {
    case inactive
    case warmingUp
    case available(measuredRateHz: Double)
    case unavailable(reason: String)
}

public enum PanelHintFeatureState: Equatable, Sendable {
    case inactive
    case disabled
    case warmingUp
    case available
    case tooDim
    case unavailable(reason: String)
}

public struct RuntimeSnapshot: Equatable, Sendable {
    public var lifecycle: RuntimeLifecycleState
    public var tap: TapFeatureState
    public var panelHint: PanelHintFeatureState

    public init(lifecycle: RuntimeLifecycleState = .stopped,
                tap: TapFeatureState = .inactive,
                panelHint: PanelHintFeatureState = .inactive) {
        self.lifecycle = lifecycle
        self.tap = tap
        self.panelHint = panelHint
    }
}

public enum RuntimeWarning: Equatable, Sendable {
    case configuration(String)
    case source(path: SensorPath?, message: String)
}

public enum RuntimeOutput: Equatable, Sendable {
    case statusChanged(RuntimeSnapshot)
    case intent(RuntimeIntent)
    case warning(RuntimeWarning)
}
