import Foundation
import MactuationCapture
import MactuationCore

/// Delivery is synchronous and in merged timestamp order, so downstream
/// processing sees exactly the same sequence on every run — the basis of the
/// project's deterministic-replay quality gate. Wall-clock pacing is
/// deliberately absent: determinism tests must not depend on timing.
public final class ReplaySensorSource: SensorSource {
    public let paths: [SensorPath]

    private let samples: [SensorSample]
    private var started = false

    public init(reader: CaptureReader) throws {
        self.samples = try reader.mergedSamples()
        self.paths = reader.manifest.sensors.map(\.path)
    }

    public init(samples: [SensorSample]) {
        self.samples = samples.sortedDeterministically()
        self.paths = Array(Set(samples.map(\.path))).sorted { $0.rawValue < $1.rawValue }
    }

    public func start(handler: @escaping (SensorSourceEvent) -> Void) throws {
        guard !started else { throw SensorSourceError.alreadyStarted }
        started = true
        for sample in samples {
            handler(.sample(sample))
        }
        handler(.completed)
    }

    public func stop() {
        started = false
    }
}
