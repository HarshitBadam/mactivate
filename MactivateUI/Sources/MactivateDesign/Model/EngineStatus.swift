import Foundation
import MactuationCore

/// The state of one trigger, as the UI must be able to show it. Every case here
/// exists because the UX rules name it: calibrating, ready, low confidence,
/// unavailable, permission required, helper disconnected.
public enum TriggerState: Equatable, Sendable {
    /// The probe has not run yet, so we genuinely do not know.
    case undetermined
    case ready
    case calibrating
    /// Working, but measured below the qualification bar on this machine.
    case lowConfidence(detail: String)
    /// Turned off by the user.
    case disabled
    case needsPermission(permission: String)
    /// Present but behind an explicit opt-in (camera/microphone).
    case needsOptIn
    case unavailable(reason: String)

    public var tone: Tone {
        switch self {
        case .undetermined: return .experimental
        case .ready: return .ready
        case .calibrating: return .attention
        case .lowConfidence: return .attention
        case .disabled: return .neutral
        case .needsPermission, .needsOptIn: return .attention
        case .unavailable: return .unavailable
        }
    }

    public var isOperating: Bool {
        if case .ready = self { return true }
        if case .lowConfidence = self { return true }
        return false
    }

    public var summary: String {
        switch self {
        case .undetermined: return "Not checked yet"
        case .ready: return "Ready"
        case .calibrating: return "Calibrating"
        case .lowConfidence(let detail): return "Low confidence — \(detail)"
        case .disabled: return "Turned off"
        case .needsPermission(let permission): return "Needs \(permission)"
        case .needsOptIn: return "Needs your approval"
        case .unavailable(let reason): return reason
        }
    }
}

/// Whether the privileged sensor helper is reachable. A lost helper is a calm,
/// explained state with a retry, not a crash and not silence.
public enum HelperState: Equatable, Sendable {
    case notRequired
    case connected(version: String)
    case connecting
    case disconnected(reason: String)

    public var tone: Tone {
        switch self {
        case .notRequired, .connected: return .ready
        case .connecting: return .attention
        case .disconnected: return .failure
        }
    }

    public var summary: String {
        switch self {
        case .notRequired: return "Not needed"
        case .connected(let version): return "Connected (\(version))"
        case .connecting: return "Connecting…"
        case .disconnected(let reason): return reason
        }
    }
}

/// A privacy-sensitive sensor that is actively capturing right now. The UI's
/// claim must always match the macOS green/orange indicator, so this is derived
/// from the engine rather than from the user's settings.
public struct ActiveCaptureStatus: Equatable, Sendable {
    public var path: SensorPath
    public var reason: String
    public var startedAt: Date

    public init(path: SensorPath, reason: String, startedAt: Date) {
        self.path = path
        self.reason = reason
        self.startedAt = startedAt
    }
}

/// Everything the UI needs to describe the engine without guessing. The engine
/// owns this; the UI only renders it.
public struct EngineStatus: Equatable, Sendable {
    /// Master switch. When paused, no gesture runs an action, and the panel says
    /// so instead of appearing broken.
    public var isPaused: Bool
    public var handNear: TriggerState
    public var tap: TriggerState
    public var helper: HelperState
    public var capabilities: CapabilityReport
    public var activeCaptures: [ActiveCaptureStatus]
    /// Which path is actually supplying hand-near and tap data right now, so the
    /// surfaces can name the active sensor as the UX rules require.
    public var activeHandNearPath: SensorPath?
    public var activeTapPath: SensorPath?
    /// Populated when the probe has run on this machine. Until then the UI must
    /// not claim any capability is validated here.
    public var probeCompletedAt: Date?
    public var machineDescription: String?

    public init(
        isPaused: Bool = false,
        handNear: TriggerState = .undetermined,
        tap: TriggerState = .undetermined,
        helper: HelperState = .notRequired,
        capabilities: CapabilityReport = .allUnknown(),
        activeCaptures: [ActiveCaptureStatus] = [],
        activeHandNearPath: SensorPath? = nil,
        activeTapPath: SensorPath? = nil,
        probeCompletedAt: Date? = nil,
        machineDescription: String? = nil
    ) {
        self.isPaused = isPaused
        self.handNear = handNear
        self.tap = tap
        self.helper = helper
        self.capabilities = capabilities
        self.activeCaptures = activeCaptures
        self.activeHandNearPath = activeHandNearPath
        self.activeTapPath = activeTapPath
        self.probeCompletedAt = probeCompletedAt
        self.machineDescription = machineDescription
    }

    public var isCapturingPrivateSensor: Bool { !activeCaptures.isEmpty }

    /// The one line the menu bar and panel header show. It leads with whatever
    /// is most wrong, because that is what the user opened the surface to learn.
    public var headline: String {
        if isPaused { return "Mactivate is paused" }
        if case .disconnected = helper { return "Sensor helper disconnected" }
        if !tap.isOperating && !handNear.isOperating { return "No sensors active" }
        if !tap.isOperating { return "Taps unavailable — \(tap.summary)" }
        if !handNear.isOperating { return "Hand wave unavailable — \(handNear.summary)" }
        return "Watching for taps and hand waves"
    }

    public var headlineTone: Tone {
        if isPaused { return .neutral }
        if case .disconnected = helper { return .failure }
        if tap.isOperating && handNear.isOperating { return .ready }
        if tap.isOperating || handNear.isOperating { return .attention }
        return .unavailable
    }
}
