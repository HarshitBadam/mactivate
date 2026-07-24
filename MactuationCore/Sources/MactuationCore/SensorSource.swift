import Foundation

/// The engine's acquisition boundary. Hardware adapters (SPU HID, DisplayServices,
/// consented fallbacks) will live behind this protocol; today the only
/// implementations are `MockSensorSource` and `ReplaySensorSource`, which is
/// deliberate — real adapters are probe deliverables.
public protocol SensorSource: AnyObject {
    var paths: [SensorPath] { get }

    /// Begins delivery. The handler may be called on any queue; callers that
    /// need serialization wrap it themselves. Sources must deliver samples in
    /// non-decreasing timestamp order per path.
    func start(handler: @escaping (SensorSample) -> Void) throws

    func stop()
}

public enum SensorSourceError: Error, Equatable {
    case alreadyStarted
    case pathUnavailable(SensorPath, reason: String)
    case captureUnreadable(String)
}
