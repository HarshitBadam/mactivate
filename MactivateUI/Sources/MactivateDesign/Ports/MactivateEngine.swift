import Foundation
import MactuationCore

/// The seam between this UI and the Mactuation Engine.
///
/// The UI is written entirely against this protocol, so the calibrated backend
/// can be dropped in by conforming one type — no view or view-model change. The
/// mock in `Mock/` conforms to the same protocol, which is what lets every state
/// (unavailable sensors, denied permissions, low confidence, disconnected
/// helper) be designed and demonstrated before the hardware code lands.
///
/// Deliberate shape notes:
/// - Everything is `async`, because sensor work must stay off the main thread.
/// - Streams are `AsyncStream`s the UI consumes in a task tied to a surface's
///   lifetime; nothing here polls.
/// - The engine reports status; the UI never infers it from settings. A user who
///   switched a fallback on and a device that is actually capturing are two
///   different facts, and the privacy rules depend on showing the second.
public protocol MactivateEngine: AnyObject, Sendable {
    /// Current status snapshot, for the first paint of a surface.
    func currentStatus() async -> EngineStatus

    /// Status updates. Must emit on capability, permission, helper, pause, and
    /// active-capture changes.
    func statusUpdates() -> AsyncStream<EngineStatus>

    /// Accepted gestures only. Ambiguous or low-confidence input must not appear
    /// here — the fail-closed rule is the engine's, and the UI trusts it.
    func gestureEvents() -> AsyncStream<GestureEvent>

    /// A normalized 0…1 signal for the live waveform: the hand-near signal when
    /// `path` is an ALS path, the tap signal envelope for an IMU path. Used for
    /// the capability "Test" panel and during calibration.
    func signalStream(for path: SensorPath) -> AsyncStream<Double>

    /// Re-run capability discovery. Returns the fresh report; the UI shows a
    /// determinate progress state while it runs.
    func runCapabilityProbe() async -> CapabilityReport

    /// Start calibration for a region and tap count. Progress arrives on the
    /// returned stream and ends with a `.finished` step.
    func calibrate(region: TapRegionID, count: TapCount) -> AsyncStream<CalibrationProgress>

    /// Start hand-near calibration ("wave over the notch a few times").
    func calibrateHandNear() -> AsyncStream<CalibrationProgress>

    /// Cancel any in-flight calibration. Must leave the previous calibration
    /// untouched.
    func cancelCalibration() async

    /// Turn a privacy-sensitive fallback on or off. Enabling must be the result
    /// of an explicit user confirmation in the UI; disabling must release the
    /// device promptly.
    func setFallback(_ path: SensorPath, enabled: Bool) async

    /// Master pause. Paused means no action fires from any gesture.
    func setPaused(_ paused: Bool) async

    /// Run an action now, from a macro-pad button or a "Test" button. Returns the
    /// outcome so the surface can acknowledge or explain.
    func run(_ action: ActionSpec, trigger: ActionTrigger) async -> ActionOutcome
}

/// Why an action ran. The engine uses it for exactly-once bookkeeping; the UI
/// uses it to label the activity feed.
public enum ActionTrigger: Equatable, Sendable {
    case tap(region: TapRegionID, count: TapCount)
    case macroPad(slot: UUID)
    case test
}

/// Where the configuration lives. Saving is atomic and versioned; the UI treats
/// a failed save as a visible error, never as a silent no-op.
public protocol ConfigurationStore: AnyObject, Sendable {
    func load() async throws -> MactivateConfiguration
    func save(_ configuration: MactivateConfiguration) async throws
    /// Location shown by the "Reveal Configuration File" fix.
    var fileURL: URL? { get }
}

public enum ConfigurationStoreError: Error, Equatable {
    case unreadable(String)
    case unwritable(String)
    case incompatibleSchema(found: Int, supported: Int)
}
