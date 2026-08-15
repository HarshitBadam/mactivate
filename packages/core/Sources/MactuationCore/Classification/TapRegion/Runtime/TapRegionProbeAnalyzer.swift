import Foundation

/// Shared by personal calibration and offline fitting so both use identical
/// qualification semantics.
public enum TapRegionProbeAnalyzer {
    public static func evaluate(
        predictions: [TapRegionProbePrediction],
        observations: [TapRegionProbeObservation]
    ) -> TapRegionQualificationMetrics {
        guard predictions.count == observations.count else {
            return TapRegionQualificationMetrics(
                total: observations.count,
                correct: 0,
                incorrect: 0,
                ambiguous: observations.count,
                leftPrecision: 0,
                rightPrecision: 0,
                groupCoverage: [:]
            )
        }
        return metrics(for: Array(zip(observations, predictions)))
    }

    private static func metrics(
        for evaluated: [(
            TapRegionProbeObservation,
            TapRegionProbePrediction
        )]
    ) -> TapRegionQualificationMetrics {
        var correct = 0
        var incorrect = 0
        var ambiguous = 0
        var predictedLeft = 0
        var predictedRight = 0
        var correctLeft = 0
        var correctRight = 0
        var totals: [String: Int] = [:]
        var groupCorrect: [String: Int] = [:]
        for side in TapRegionProbeSide.allCases {
            for intensity in TapRegionProbeIntensity.allCases {
                totals[groupKey(side: side, intensity: intensity)] = 0
            }
        }

        for (observation, prediction) in evaluated {
            let key = groupKey(
                side: observation.side,
                intensity: observation.intensity
            )
            totals[key, default: 0] += 1
            switch prediction {
            case .ambiguous:
                ambiguous += 1
            case .left:
                predictedLeft += 1
                if observation.side == .left {
                    correct += 1
                    correctLeft += 1
                    groupCorrect[key, default: 0] += 1
                } else {
                    incorrect += 1
                }
            case .right:
                predictedRight += 1
                if observation.side == .right {
                    correct += 1
                    correctRight += 1
                    groupCorrect[key, default: 0] += 1
                } else {
                    incorrect += 1
                }
            }
        }

        let coverage = Dictionary(
            uniqueKeysWithValues: totals.map { key, count in
                (key, count == 0 ? 0 :
                    Double(groupCorrect[key, default: 0]) / Double(count))
            }
        )
        return TapRegionQualificationMetrics(
            total: evaluated.count,
            correct: correct,
            incorrect: incorrect,
            ambiguous: ambiguous,
            leftPrecision: predictedLeft == 0 ? 0 :
                Double(correctLeft) / Double(predictedLeft),
            rightPrecision: predictedRight == 0 ? 0 :
                Double(correctRight) / Double(predictedRight),
            groupCoverage: coverage
        )
    }

    private static func groupKey(
        side: TapRegionProbeSide,
        intensity: TapRegionProbeIntensity
    ) -> String {
        "\(side.rawValue)-\(intensity.rawValue)"
    }
}
