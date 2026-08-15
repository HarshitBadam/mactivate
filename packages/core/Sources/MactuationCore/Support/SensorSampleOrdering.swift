import Foundation

public extension Array where Element == SensorSample {
    /// Deterministic merge order shared by capture reading, mock generation,
    /// and replay: ascending timestamp, then sensor path name, then original
    /// position. Ties are broken by original position rather than left to
    /// sort stability, so every consumer reproduces the same order from the
    /// same input regardless of `Array.sorted`'s implementation.
    func sortedDeterministically() -> [SensorSample] {
        enumerated().sorted {
            ($0.element.timestamp, $0.element.path.rawValue, $0.offset) <
                ($1.element.timestamp, $1.element.path.rawValue, $1.offset)
        }.map(\.element)
    }
}
