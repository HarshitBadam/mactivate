import Foundation

extension Array where Element == Double {
    /// Callers must pre-sort and ensure `self` is non-empty.
    /// Shared by tap-region calibration building and live stream
    /// classification so personal calibration and runtime classification
    /// compute "median" identically.
    var medianOfSorted: Double {
        let middle = count / 2
        return count.isMultiple(of: 2)
            ? (self[middle - 1] + self[middle]) / 2
            : self[middle]
    }
}
