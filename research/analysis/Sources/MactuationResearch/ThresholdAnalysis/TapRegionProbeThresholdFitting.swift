import Foundation
import MactuationCore

/// Offline single-feature threshold fitting and qualification for the
/// region probe. Scoring predictions against observations
/// (`evaluate(predictions:observations:)`) is a runtime-reachable Core
/// primitive that production calibration also uses; every fitting entry
/// point here delegates to it so a personal calibration is held to the
/// same metric a research fit is qualified against.
extension TapRegionProbeAnalyzer {
    public static func fit(
        _ observations: [TapRegionProbeObservation]
    ) throws -> TapRegionThresholdFit {
        try fit(
            observations,
            featureNames: TapRegionProbeObservation.modelFeatureNames
        )
    }

    public static func fit(
        _ observations: [TapRegionProbeObservation],
        featureNames: [String]
    ) throws -> TapRegionThresholdFit {
        guard let best = try rankedFits(
            observations,
            featureNames: featureNames
        ).first else {
            throw TapRegionProbeAnalysisError.insufficientObservations
        }
        return best
    }

    public static func rankedFits(
        _ observations: [TapRegionProbeObservation]
    ) throws -> [TapRegionThresholdFit] {
        try rankedFits(
            observations,
            featureNames: TapRegionProbeObservation.modelFeatureNames
        )
    }

    public static func rankedFits(
        _ observations: [TapRegionProbeObservation],
        featureNames: [String]
    ) throws -> [TapRegionThresholdFit] {
        try validateCoverage(observations)
        var fits: [TapRegionThresholdFit] = []

        for feature in featureNames {
            if let fit = try? fitThreshold(
                featureName: feature,
                observations: observations
            ) {
                fits.append(fit)
            }
        }
        return fits.sorted {
            isBetter($0, than: $1)
        }
    }

    public static func fitThreshold(
        featureName: String,
        observations: [TapRegionProbeObservation]
    ) throws -> TapRegionThresholdFit {
        try validateCoverage(observations)
        let values = observations.compactMap {
            $0.features[featureName]
        }.sorted()
        guard values.count == observations.count else {
            throw TapRegionProbeAnalysisError.insufficientObservations
        }
        let boundaries = candidateBoundaries(values)
        var best: TapRegionThresholdFit?
        for lowerIndex in boundaries.indices {
            for upperIndex in lowerIndex..<boundaries.count {
                for lowerSide in TapRegionProbeSide.allCases {
                    let model = TapRegionThresholdModel(
                        featureName: featureName,
                        lowerBoundary: boundaries[lowerIndex],
                        upperBoundary: boundaries[upperIndex],
                        lowerSide: lowerSide
                    )
                    let fit = TapRegionThresholdFit(
                        model: model,
                        metrics: evaluate(model, observations: observations)
                    )
                    if isBetter(fit, than: best) {
                        best = fit
                    }
                }
            }
        }
        guard let best else {
            throw TapRegionProbeAnalysisError.insufficientObservations
        }
        return best
    }

    public static func crossValidate(
        _ observations: [TapRegionProbeObservation],
        folds: Int = 5,
        featureNames: [String] = TapRegionProbeObservation.modelFeatureNames
    ) throws -> TapRegionCrossValidationResult {
        try validateCoverage(observations)
        guard folds >= 2 else {
            throw TapRegionProbeAnalysisError.insufficientObservations
        }
        var evaluated: [(
            TapRegionProbeObservation,
            TapRegionProbePrediction
        )] = []
        var models: [TapRegionThresholdModel] = []

        for fold in 0..<folds {
            let heldOut = observations.filter {
                max(0, $0.repetition - 1) % folds == fold
            }
            let training = observations.filter {
                max(0, $0.repetition - 1) % folds != fold
            }
            guard !heldOut.isEmpty else {
                throw TapRegionProbeAnalysisError.insufficientObservations
            }
            let fit = try self.fit(
                training,
                featureNames: featureNames
            )
            models.append(fit.model)
            evaluated += heldOut.map {
                ($0, fit.model.predict($0))
            }
        }
        return TapRegionCrossValidationResult(
            metrics: TapRegionProbeAnalyzer.evaluate(
                predictions: evaluated.map(\.1),
                observations: evaluated.map(\.0)
            ),
            foldModels: models
        )
    }

    public static func evaluate(
        _ model: TapRegionThresholdModel,
        observations: [TapRegionProbeObservation]
    ) -> TapRegionQualificationMetrics {
        TapRegionProbeAnalyzer.evaluate(
            predictions: observations.map(model.predict),
            observations: observations
        )
    }

    private static func validateCoverage(
        _ observations: [TapRegionProbeObservation]
    ) throws {
        for side in TapRegionProbeSide.allCases {
            for intensity in TapRegionProbeIntensity.allCases
            where !observations.contains(where: {
                $0.side == side && $0.intensity == intensity
            }) {
                throw TapRegionProbeAnalysisError.insufficientObservations
            }
        }
    }

    private static func candidateBoundaries(_ sortedValues: [Double])
        -> [Double] {
        guard let first = sortedValues.first, let last = sortedValues.last else {
            return []
        }
        let scale = max(1, max(abs(first), abs(last)))
        var boundaries = [first - scale * 1e-9]
        for (left, right) in zip(sortedValues, sortedValues.dropFirst())
        where left < right {
            boundaries.append(left + (right - left) / 2)
        }
        boundaries.append(last + scale * 1e-9)
        return boundaries
    }

    private static func isBetter(
        _ candidate: TapRegionThresholdFit,
        than current: TapRegionThresholdFit?
    ) -> Bool {
        guard let current else { return true }
        let candidateScore = candidate.metrics.fitRankingScore
        let currentScore = current.metrics.fitRankingScore
        if candidateScore != currentScore {
            return candidateScore.lexicographicallyPrecedes(currentScore) == false
        }
        let candidateKey = "\(candidate.model.featureName)/" +
            "\(candidate.model.lowerSide.rawValue)/" +
            "\(candidate.model.lowerBoundary)/\(candidate.model.upperBoundary)"
        let currentKey = "\(current.model.featureName)/" +
            "\(current.model.lowerSide.rawValue)/" +
            "\(current.model.lowerBoundary)/\(current.model.upperBoundary)"
        return candidateKey < currentKey
    }
}
