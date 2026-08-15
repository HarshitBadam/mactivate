import Foundation
import MactuationCore

/// Ranking key threshold, linear-discriminant, and multi-tap-vote fitting
/// all sort candidate fits by: qualifies first, then coverage, worst-side
/// precision, classified fraction, and fewest incorrect, in that order, so
/// "better fit" means the same thing across every research fitting path.
extension TapRegionQualificationMetrics {
    var fitRankingScore: [Double] {
        [
            qualifies ? 1 : 0,
            minimumGroupCoverage,
            min(leftPrecision, rightPrecision),
            classifiedFraction,
            -Double(incorrect)
        ]
    }
}
