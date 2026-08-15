import Foundation
import MactuationCore

public enum TapRegionLinearProbeAnalyzer {
    public static let candidateFeatureSets: [(name: String, features: [String])] = [
        ("accel-impulse-xyz", axes("accel_%@_impulse_25_mg_s")),
        ("gyro-impulse-10-xyz", axes("gyro_%@_impulse_10_deg")),
        ("gyro-impulse-25-xyz", axes("gyro_%@_impulse_25_deg")),
        ("gyro-impulse-50-xyz", axes("gyro_%@_impulse_50_deg")),
        ("gyro-peak-xyz", axes("gyro_%@_peak_deg_s")),
        ("gyro-at-impact-xyz", axes("gyro_%@_at_accel_peak_deg_s")),
        ("gyro-post-10-xyz", axes("gyro_%@_post_impulse_10_deg")),
        ("gyro-post-25-xyz", axes("gyro_%@_post_impulse_25_deg")),
        ("gyro-post-50-xyz", axes("gyro_%@_post_impulse_50_deg")),
        ("gyro-peak-balance-xyz", axes("gyro_%@_peak_balance_deg_s")),
        ("gyro-phase-delta-xyz", axes("gyro_%@_post_pre_delta_25_deg")),
        (
            "gyro-impact-and-balance",
            axes("gyro_%@_at_accel_peak_deg_s") +
                axes("gyro_%@_peak_balance_deg_s")
        ),
        (
            "gyro-peak-and-phase",
            axes("gyro_%@_peak_deg_s") +
                axes("gyro_%@_post_pre_delta_25_deg")
        ),
        (
            "gyro-compact-waveform",
            axes("gyro_%@_at_accel_peak_deg_s") +
                axes("gyro_%@_post_impulse_25_deg") +
                axes("gyro_%@_peak_balance_deg_s")
        )
    ]

    public static func fit(
        _ observations: [TapRegionProbeObservation]
    ) throws -> TapRegionLinearFit {
        guard let best = try rankedFits(observations).first else {
            throw TapRegionProbeAnalysisError.insufficientObservations
        }
        return best
    }

    public static func rankedFits(
        _ observations: [TapRegionProbeObservation]
    ) throws -> [TapRegionLinearFit] {
        var fits: [TapRegionLinearFit] = []
        for candidate in candidateFeatureSets {
            if let fit = try? fit(
                observations,
                name: candidate.name,
                featureNames: candidate.features,
                ridge: 0.5
            ) {
                fits.append(fit)
            }
        }
        return fits.sorted { isBetter($0, than: $1) }
    }

    public static func crossValidate(
        _ observations: [TapRegionProbeObservation],
        folds: Int = 5
    ) throws -> TapRegionLinearCrossValidationResult {
        guard folds >= 2 else {
            throw TapRegionProbeAnalysisError.insufficientObservations
        }
        var heldOutObservations: [TapRegionProbeObservation] = []
        var predictions: [TapRegionProbePrediction] = []
        var models: [TapRegionLinearModel] = []

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
            let fit = try self.fit(training)
            models.append(fit.model)
            heldOutObservations += heldOut
            predictions += heldOut.map { fit.model.predict($0) }
        }
        return TapRegionLinearCrossValidationResult(
            metrics: TapRegionProbeAnalyzer.evaluate(
                predictions: predictions,
                observations: heldOutObservations
            ),
            foldModels: models
        )
    }

    private static func axes(_ format: String) -> [String] {
        ["x", "y", "z"].map { String(format: format, $0) }
    }

    private static func isBetter(
        _ candidate: TapRegionLinearFit,
        than current: TapRegionLinearFit
    ) -> Bool {
        let candidateScore = candidate.metrics.fitRankingScore
        let currentScore = current.metrics.fitRankingScore
        if candidateScore != currentScore {
            return !candidateScore.lexicographicallyPrecedes(currentScore)
        }
        return candidate.model.name < current.model.name
    }
}
