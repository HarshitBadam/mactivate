import Foundation
import MactuationCore

/// Cross-validated screening across every aggregation and per-member vote
/// strategy, so a research fit can pick the one that best transfers to
/// held-out repetitions before committing to a production strategy.
extension TapRegionMultiTapProbeAnalyzer {
    public static func screen(
        _ gestures: [TapRegionMultiTapGesture],
        folds requestedFolds: Int = 5
    ) throws -> [TapRegionMultiTapStrategyResult] {
        let repetitionCount = Set(gestures.map(\.repetition)).count
        let folds = min(requestedFolds, repetitionCount)
        guard folds >= 2 else {
            throw TapRegionMultiTapAnalysisError.insufficientRepetitions
        }
        var results: [TapRegionMultiTapStrategyResult] = []
        for aggregation in TapRegionMultiTapAggregation.allCases {
            results.append(try screenAggregation(
                aggregation,
                gestures: gestures,
                folds: folds
            ))
        }
        for vote in TapRegionMultiTapVote.allCases {
            results.append(try screenVote(
                vote,
                gestures: gestures,
                folds: folds
            ))
        }
        return results.sorted {
            let leftScore = $0.crossValidationMetrics.fitRankingScore
            let rightScore = $1.crossValidationMetrics.fitRankingScore
            if leftScore != rightScore {
                return !leftScore.lexicographicallyPrecedes(rightScore)
            }
            return $0.name < $1.name
        }
    }

    private static func screenAggregation(
        _ aggregation: TapRegionMultiTapAggregation,
        gestures: [TapRegionMultiTapGesture],
        folds: Int
    ) throws -> TapRegionMultiTapStrategyResult {
        let observations = gestures.map {
            aggregate($0, using: aggregation)
        }
        let training = try TapRegionProbeAnalyzer.fit(
            observations,
            featureNames: candidateFeatureNames
        )
        let crossValidation = try TapRegionProbeAnalyzer.crossValidate(
            observations,
            folds: folds,
            featureNames: candidateFeatureNames
        )
        return TapRegionMultiTapStrategyResult(
            name: aggregation.rawValue,
            trainingMetrics: training.metrics,
            crossValidationMetrics: crossValidation.metrics,
            selectedFeatures: Dictionary(
                grouping: crossValidation.foldModels,
                by: \.featureName
            ).mapValues(\.count)
        )
    }

    private static func screenVote(
        _ vote: TapRegionMultiTapVote,
        gestures: [TapRegionMultiTapGesture],
        folds: Int
    ) throws -> TapRegionMultiTapStrategyResult {
        let trainingFit = try bestVoteFit(gestures: gestures, vote: vote)
        var heldOutObservations: [TapRegionProbeObservation] = []
        var predictions: [TapRegionProbePrediction] = []
        var selectedFeatures: [String: Int] = [:]

        for fold in 0..<folds {
            let training = gestures.filter {
                max(0, $0.repetition - 1) % folds != fold
            }
            let heldOut = gestures.filter {
                max(0, $0.repetition - 1) % folds == fold
            }
            let fit = try bestVoteFit(gestures: training, vote: vote)
            selectedFeatures[fit.model.featureName, default: 0] += 1
            heldOutObservations += heldOut.map {
                aggregate($0, using: .firstMember)
            }
            predictions += heldOut.map {
                prediction(for: $0, model: fit.model, vote: vote)
            }
        }
        return TapRegionMultiTapStrategyResult(
            name: vote.rawValue,
            trainingMetrics: trainingFit.metrics,
            crossValidationMetrics: TapRegionProbeAnalyzer.evaluate(
                predictions: predictions,
                observations: heldOutObservations
            ),
            selectedFeatures: selectedFeatures
        )
    }

    static func prediction(
        for gesture: TapRegionMultiTapGesture,
        model: TapRegionThresholdModel,
        vote: TapRegionMultiTapVote
    ) -> TapRegionProbePrediction {
        let memberPredictions = gesture.members.map(model.predict)
        let left = memberPredictions.filter { $0 == .left }.count
        let right = memberPredictions.filter { $0 == .right }.count
        switch vote {
        case .unanimous:
            if left == gesture.members.count { return .left }
            if right == gesture.members.count { return .right }
        case .majority:
            if left > gesture.members.count / 2 { return .left }
            if right > gesture.members.count / 2 { return .right }
        }
        return .ambiguous
    }
}
