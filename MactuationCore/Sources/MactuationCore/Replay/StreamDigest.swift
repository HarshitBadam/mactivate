import Foundation

/// Order-sensitive digest over a sample or event sequence, used to assert
/// byte-for-byte identical replay output. FNV-1a over the canonical CSV
/// encoding keeps the digest independent of Foundation hashing seeds.
public struct StreamDigest: Equatable, Sendable {
    private var state: UInt64 = 0xcbf29ce484222325

    public init() {}

    public mutating func update(_ sample: SensorSample) {
        update(string: sample.path.rawValue)
        update(string: CaptureFormat.csvLine(for: sample))
    }

    public mutating func update(string: String) {
        for byte in string.utf8 {
            state ^= UInt64(byte)
            state = state &* 0x100000001b3
        }
        // Field separator so concatenated inputs can't collide.
        state ^= 0x1e
        state = state &* 0x100000001b3
    }

    public var value: String {
        String(format: "%016llx", state)
    }

    public static func digest(of samples: [SensorSample]) -> String {
        var digest = StreamDigest()
        for sample in samples {
            digest.update(sample)
        }
        return digest.value
    }
}
