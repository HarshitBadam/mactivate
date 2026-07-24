import Dispatch

public final class SensorProcessingQueue: @unchecked Sendable {
    private let queue: DispatchQueue

    public init(label: String = "com.mactivate.sensor-processing") {
        queue = DispatchQueue(label: label, qos: .userInitiated)
    }

    public func submit(_ sample: SensorSample, handler: @escaping @Sendable (SensorSample) -> Void) {
        queue.async {
            handler(sample)
        }
    }

    public func finish() {
        queue.sync {}
    }
}
