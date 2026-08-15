import Foundation
import MactuationCore

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
    public let gesture: PalmTapGesture
    public let sensorTimestamp: SensorTimestamp
    public let regionProfileVersion: String

    public init(
        eventID: RuntimeEventID,
        gesture: PalmTapGesture,
        sensorTimestamp: SensorTimestamp,
        regionProfileVersion: String
    ) {
        self.eventID = eventID
        self.gesture = gesture
        self.sensorTimestamp = sensorTimestamp
        self.regionProfileVersion = regionProfileVersion
    }

    public var pattern: TapPattern {
        gesture.pattern == .double ? .double : .triple
    }
}

public enum PanelPresentationReason: Equatable, Sendable {
    case ambientLightHint
}

public enum RuntimeIntent: Equatable, Sendable {
    case performAction(id: ActionIdentifier, trigger: TapTrigger)
    case showPanel(reason: PanelPresentationReason, hint: PanelOpenHint)
}

public enum RuntimeWarning: Equatable, Sendable {
    case configuration(String)
    case source(path: SensorPath?, message: String)
}

public enum RuntimeOutput: Equatable, Sendable {
    case statusChanged(RuntimeSnapshot)
    case tapFeedback(TapFeedback)
    case intent(RuntimeIntent)
    case warning(RuntimeWarning)
}
