import Foundation

/// The sections of the notch panel. Three, because the panel is glanced at, not
/// browsed: what my taps do, what I can press, and whether it is working.
public enum PanelTab: String, CaseIterable, Identifiable, Sendable {
    case taps
    case macroPad
    case status

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .taps: return "Taps"
        case .macroPad: return "Macro Pad"
        case .status: return "Status"
        }
    }

    public var symbolName: String {
        switch self {
        case .taps: return "hand.tap"
        case .macroPad: return "square.grid.2x2"
        case .status: return "waveform"
        }
    }
}

public enum PanelOpenReason: Equatable, Sendable {
    case handNear
    case hotkey
    case menuBar
    case pointer
}

/// The notch panel's presentation state machine.
///
/// It exists as a testable value type because the panel's hardest requirement is
/// behavioural, not visual: it must never steal focus, never trap the pointer,
/// and never retract while the user is mid-edit. Those are timing rules, and
/// timing rules belong somewhere they can be asserted.
public struct PanelPresentation: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        /// A hairline presence at the notch.
        case closed
        /// The hand-near signal is rising but has not resolved. Shows a subtle
        /// widening of the notch presence — an invitation, not a commitment.
        case armed
        /// Open because of a physical trigger. Retracts on its own when the hand
        /// leaves, because the user has not committed to anything yet.
        case open(reason: PanelOpenReason)
        /// Open and staying open: the user clicked, typed, or opened it
        /// deliberately. Only an explicit dismissal closes it.
        case held(reason: PanelOpenReason)
    }

    public enum Event: Equatable, Sendable {
        case handNearBegan
        case handNearResolved
        case handNearEnded
        case hotkeyPressed
        case menuBarOpenRequested
        case pointerEnteredHoverZone
        case pointerEnteredPanel
        case userInteracted
        case autoDismissElapsed
        case dismissRequested
        /// Display change, sleep/wake, or screen reconfiguration: return to a
        /// known state rather than trying to preserve a stale one.
        case environmentChanged
    }

    public private(set) var state: State = .closed
    public var tab: PanelTab = .taps
    /// True while an auto-dismiss countdown should be running. The view layer
    /// owns the timer; this owns whether one should exist.
    public private(set) var isAutoDismissArmed = false

    public init() {}

    public var isVisible: Bool {
        switch state {
        case .closed: return false
        case .armed, .open, .held: return true
        }
    }

    public var isExpanded: Bool {
        switch state {
        case .open, .held: return true
        case .closed, .armed: return false
        }
    }

    /// Whether the window should accept clicks. A closed or merely armed panel
    /// stays click-through so it cannot swallow a click meant for the app
    /// underneath.
    public var acceptsPointerInput: Bool { isExpanded }

    /// Whether opening should activate Mactivate. Only ever true when the user
    /// asked for the app by name — the physical trigger must not take focus from
    /// whatever they were typing in.
    public var shouldActivateApp: Bool {
        switch state {
        case .held(let reason): return reason == .menuBar
        default: return false
        }
    }

    public mutating func handle(_ event: Event) {
        switch event {
        case .handNearBegan:
            if case .closed = state { state = .armed }

        case .handNearResolved:
            switch state {
            case .closed, .armed:
                state = .open(reason: .handNear)
                isAutoDismissArmed = false
            case .open, .held:
                break
            }

        case .handNearEnded:
            switch state {
            case .armed:
                state = .closed
            case .open:
                // The hand left, but the panel stays up long enough to be read
                // and reached with the pointer.
                isAutoDismissArmed = true
            case .closed, .held:
                break
            }

        case .hotkeyPressed:
            if isExpanded {
                closeNow()
            } else {
                state = .held(reason: .hotkey)
                isAutoDismissArmed = false
            }

        case .menuBarOpenRequested:
            state = .held(reason: .menuBar)
            isAutoDismissArmed = false

        case .pointerEnteredHoverZone:
            if case .closed = state { state = .armed }

        case .pointerEnteredPanel:
            if case .open(let reason) = state {
                state = .held(reason: reason)
            }
            isAutoDismissArmed = false

        case .userInteracted:
            switch state {
            case .open(let reason):
                state = .held(reason: reason)
            case .armed:
                state = .held(reason: .pointer)
            case .closed, .held:
                break
            }
            isAutoDismissArmed = false

        case .autoDismissElapsed:
            if isAutoDismissArmed, case .open = state {
                closeNow()
            }

        case .dismissRequested:
            closeNow()

        case .environmentChanged:
            closeNow()
        }
    }

    private mutating func closeNow() {
        state = .closed
        isAutoDismissArmed = false
    }
}
