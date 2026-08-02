import Foundation

/// An accepted gesture, as delivered by the engine. `id` is the engine's stable
/// event identifier: the UI deduplicates on it so a reconnecting helper or a
/// replayed stream can never make one tap look like two.
public struct GestureEvent: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case tap(region: TapRegionID, count: TapCount)
        case handNear
        /// The user clicked a macro-pad button. Recorded in the same feed so the
        /// activity list is the honest history of what ran.
        case macroPad(slot: UUID)
        /// The panel hotkey.
        case hotkey
    }

    public var id: String
    public var kind: Kind
    public var confidence: Double
    public var timestamp: Date

    public init(id: String, kind: Kind, confidence: Double, timestamp: Date) {
        self.id = id
        self.kind = kind
        self.confidence = confidence
        self.timestamp = timestamp
    }
}

/// What happened when an action ran. Failures are shown, never swallowed.
public enum ActionOutcome: Equatable, Sendable {
    case ran
    case noBinding
    case skippedPaused
    case failed(reason: String)

    public var tone: Tone {
        switch self {
        case .ran: return .ready
        case .noBinding, .skippedPaused: return .neutral
        case .failed: return .failure
        }
    }
}

/// One row in the activity feed: a gesture, what it was bound to, and how the
/// run went.
public struct ActivityEntry: Identifiable, Equatable, Sendable {
    public var id: String
    public var event: GestureEvent
    public var actionTitle: String?
    public var actionSymbolName: String?
    public var outcome: ActionOutcome

    public init(
        event: GestureEvent,
        actionTitle: String?,
        actionSymbolName: String?,
        outcome: ActionOutcome
    ) {
        self.id = event.id
        self.event = event
        self.actionTitle = actionTitle
        self.actionSymbolName = actionSymbolName
        self.outcome = outcome
    }

    public var symbolName: String {
        if let actionSymbolName { return actionSymbolName }
        switch event.kind {
        case .tap(_, let count): return count.symbolName
        case .handNear: return "hand.wave"
        case .macroPad: return "square.grid.2x2"
        case .hotkey: return "command"
        }
    }
}

/// The recent-activity feed. Bounded, deduplicated by event ID, newest first.
///
/// This is the UI half of the exactly-once rule: even if the engine redelivers
/// an event after a reconnect, it appears once here, and a duplicate is counted
/// so Diagnostics can show that it was suppressed rather than hiding it.
public struct ActivityFeed: Equatable, Sendable {
    public static let capacity = 50

    public private(set) var entries: [ActivityEntry] = []
    public private(set) var suppressedDuplicateCount = 0

    public init() {}

    /// Returns `true` when the entry was new. `false` means a duplicate event ID
    /// was suppressed.
    @discardableResult
    public mutating func record(_ entry: ActivityEntry) -> Bool {
        if entries.contains(where: { $0.id == entry.id }) {
            suppressedDuplicateCount += 1
            return false
        }
        entries.insert(entry, at: 0)
        if entries.count > ActivityFeed.capacity {
            entries.removeLast(entries.count - ActivityFeed.capacity)
        }
        return true
    }

    public var mostRecent: ActivityEntry? { entries.first }

    public mutating func clear() {
        entries.removeAll()
        suppressedDuplicateCount = 0
    }
}
