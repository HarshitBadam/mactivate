import Foundation
import MactuationCapture
import MactuationCore

/// Order-sensitive digest over a sample or event sequence, used to assert
/// byte-for-byte identical replay output. Wraps Core's generic
/// `DeterministicDigest` with the capture-specific per-sample encoding, so
/// both share one FNV-1a implementation independent of Foundation hashing
/// seeds.
public struct StreamDigest: Equatable, Sendable {
    private var digest = DeterministicDigest()

    public init() {}

    public mutating func update(_ sample: SensorSample) {
        update(string: sample.path.rawValue)
        update(string: CaptureFormat.csvLine(for: sample))
    }

    public mutating func update(string: String) {
        digest.update(string: string)
    }

    public var value: String {
        digest.value
    }

    public static func digest(of samples: [SensorSample]) -> String {
        var result = StreamDigest()
        for sample in samples {
            result.update(sample)
        }
        return result.value
    }
}
