import Foundation

/// Fixed-capacity ring of normalized samples for the live "Test" waveform.
///
/// The waveform exists to answer one question honestly — *is this sensor giving
/// my Mac anything?* — so it draws whatever arrives, including a flat line. A
/// flat line is the correct picture of an unavailable sensor, and animating a
/// placeholder there would be a lie.
public struct WaveformBuffer: Equatable, Sendable {
    public let capacity: Int
    public private(set) var samples: [Double] = []

    public init(capacity: Int = 180) {
        self.capacity = max(2, capacity)
    }

    public mutating func append(_ value: Double) {
        samples.append(min(1, max(0, value)))
        if samples.count > capacity {
            samples.removeFirst(samples.count - capacity)
        }
    }

    public mutating func clear() { samples.removeAll() }

    /// Padded to full width with the baseline so the trace scrolls in from the
    /// right instead of stretching as it fills.
    public func plotPoints(baseline: Double = 0.5) -> [Double] {
        guard samples.count < capacity else { return samples }
        return Array(repeating: baseline, count: capacity - samples.count) + samples
    }

    public var isSilent: Bool {
        guard let first = samples.first else { return true }
        return samples.allSatisfy { abs($0 - first) < 0.001 }
    }

    public var peak: Double { samples.max() ?? 0 }

    /// Peak over the last `count` samples, used for the level meter next to the
    /// trace.
    public func recentPeak(window count: Int = 20) -> Double {
        samples.suffix(count).max() ?? 0
    }
}
