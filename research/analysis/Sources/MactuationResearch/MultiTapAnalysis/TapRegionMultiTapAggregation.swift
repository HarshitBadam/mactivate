import Foundation
import MactuationCore

public enum TapRegionMultiTapProbeAnalyzer {
    static let candidateFeatureNames = [
        "accel_peak_g",
        "accel_x_impulse_25_mg_s",
        "accel_y_impulse_25_mg_s",
        "gyro_x_impulse_10_deg",
        "gyro_x_impulse_25_deg",
        "gyro_x_impulse_50_deg",
        "gyro_x_peak_deg_s",
        "gyro_x_at_accel_peak_deg_s",
        "gyro_x_peak_balance_deg_s",
        "gyro_x_post_pre_delta_25_deg",
        "gyro_x_signed_energy_fraction_50",
        "gyro_y_post_impulse_50_deg"
    ]

    struct VoteFit {
        var model: TapRegionThresholdModel
        var metrics: TapRegionQualificationMetrics
    }

    public static func fitStrategies(
        _ gestures: [TapRegionMultiTapGesture]
    ) throws -> [TapRegionMultiTapFittedStrategy] {
        var fitted: [TapRegionMultiTapFittedStrategy] = []
        for aggregation in TapRegionMultiTapAggregation.allCases {
            let observations = gestures.map {
                aggregate($0, using: aggregation)
            }
            let fit = try TapRegionProbeAnalyzer.fit(
                observations,
                featureNames: candidateFeatureNames
            )
            fitted.append(TapRegionMultiTapFittedStrategy(
                strategy: .aggregation(aggregation),
                model: fit.model,
                trainingMetrics: fit.metrics
            ))
        }
        for vote in TapRegionMultiTapVote.allCases {
            let fit = try bestVoteFit(gestures: gestures, vote: vote)
            fitted.append(TapRegionMultiTapFittedStrategy(
                strategy: .vote(vote),
                model: fit.model,
                trainingMetrics: fit.metrics
            ))
        }
        return fitted
    }

    public static func evaluate(
        _ fitted: TapRegionMultiTapFittedStrategy,
        gestures: [TapRegionMultiTapGesture]
    ) -> TapRegionQualificationMetrics {
        let observations = gestures.map {
            aggregate($0, using: .firstMember)
        }
        let predictions: [TapRegionProbePrediction]
        switch fitted.strategy {
        case .aggregation(let aggregation):
            predictions = gestures.map {
                fitted.model.predict(aggregate($0, using: aggregation))
            }
        case .vote(let vote):
            predictions = gestures.map {
                prediction(for: $0, model: fitted.model, vote: vote)
            }
        }
        return TapRegionProbeAnalyzer.evaluate(
            predictions: predictions,
            observations: observations
        )
    }

    public static func aggregate(
        _ gesture: TapRegionMultiTapGesture,
        using aggregation: TapRegionMultiTapAggregation
    ) -> TapRegionProbeObservation {
        let names = TapRegionProbeObservation.modelFeatureNames
        var features: [String: Double] = [:]
        for name in names {
            let values = gesture.members.compactMap {
                $0.features[name]
            }.sorted()
            guard values.count == gesture.members.count else { continue }
            switch aggregation {
            case .firstMember:
                features[name] = gesture.members.first?.features[name]
            case .meanMembers:
                features[name] = values.reduce(0, +) / Double(values.count)
            case .medianMembers:
                let middle = values.count / 2
                features[name] = values.count.isMultiple(of: 2)
                    ? (values[middle - 1] + values[middle]) / 2
                    : values[middle]
            }
        }
        return TapRegionProbeObservation(
            side: gesture.side,
            intensity: gesture.pattern.analysisIntensity,
            repetition: gesture.repetition,
            peakTimestamp: gesture.members.first?.peakTimestamp ?? 0,
            features: features
        )
    }

    static func bestVoteFit(
        gestures: [TapRegionMultiTapGesture],
        vote: TapRegionMultiTapVote
    ) throws -> VoteFit {
        let members = gestures.flatMap(\.members)
        let fits = try TapRegionProbeAnalyzer.rankedFits(
            members,
            featureNames: candidateFeatureNames
        )
        guard let best = fits.map({ fit -> VoteFit in
            let observations = gestures.map {
                aggregate($0, using: .firstMember)
            }
            let predictions = gestures.map {
                prediction(for: $0, model: fit.model, vote: vote)
            }
            return VoteFit(
                model: fit.model,
                metrics: TapRegionProbeAnalyzer.evaluate(
                    predictions: predictions,
                    observations: observations
                )
            )
        }).sorted(by: {
            let leftScore = $0.metrics.fitRankingScore
            let rightScore = $1.metrics.fitRankingScore
            if leftScore != rightScore {
                return !leftScore.lexicographicallyPrecedes(rightScore)
            }
            return $0.model.featureName < $1.model.featureName
        }).first else {
            throw TapRegionProbeAnalysisError.insufficientObservations
        }
        return best
    }
}
