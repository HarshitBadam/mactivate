import Foundation

/// Everything a source can report after startup. Hardware failures can happen
/// asynchronously, so they must travel over the same serialized boundary as
/// samples instead of being silently dropped.
public enum SensorSourceEvent: Equatable, Sendable {
    case sample(SensorSample)
    case failed(path: SensorPath?, reason: String)
    case warning(path: SensorPath?, message: String)
    case completed
}

/// The engine's acquisition boundary. Core provides mock and replay sources;
/// macOS adapters are provided by the `MactuationHardware` product.
public protocol SensorSource: AnyObject {
    var paths: [SensorPath] { get }

    /// Begins delivery. The handler may be called on any queue; callers that
    /// need serialization wrap it themselves. Sample events are delivered in
    /// non-decreasing timestamp order per path.
    func start(handler: @escaping (SensorSourceEvent) -> Void) throws

    /// Stops future delivery. Implementations are idempotent.
    func stop()
}

public enum SensorSourceError: Error, Equatable {
    case alreadyStarted
    case pathUnavailable(SensorPath, reason: String)
    case captureUnreadable(String)
}
