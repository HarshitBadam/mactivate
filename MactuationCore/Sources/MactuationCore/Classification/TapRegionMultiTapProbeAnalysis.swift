import Foundation

public typealias TapRegionMultiTapPattern = TapRegionPattern

public extension TapRegionPattern {
    var analysisIntensity: TapRegionProbeIntensity {
        switch self {
        case .double: return .comfort
        case .triple: return .firm
        }
    }
}

public struct TapRegionMultiTapGesture: Equatable, Sendable {
    public var side: TapRegionProbeSide
    public var pattern: TapRegionMultiTapPattern
    public var repetition: Int
    public var members: [TapRegionProbeObservation]

    public init(
        side: TapRegionProbeSide,
        pattern: TapRegionMultiTapPattern,
        repetition: Int,
        members: [TapRegionProbeObservation]
    ) {
        self.side = side
        self.pattern = pattern
        self.repetition = repetition
        self.members = members
    }
}

public enum TapRegionMultiTapAggregation: String, CaseIterable, Equatable, Sendable {
    case firstMember = "first-member"
    case meanMembers = "mean-members"
    case medianMembers = "median-members"
}

public enum TapRegionMultiTapVote: String, CaseIterable, Equatable, Sendable {
    case unanimous = "unanimous-vote"
    case majority = "majority-vote"
}

public enum TapRegionMultiTapStrategy: Equatable, Sendable {
    case aggregation(TapRegionMultiTapAggregation)
    case vote(TapRegionMultiTapVote)

    public var name: String {
        switch self {
        case .aggregation(let value): return value.rawValue
        case .vote(let value): return value.rawValue
        }
    }
}

public struct TapRegionMultiTapFittedStrategy: Equatable, Sendable {
    public var strategy: TapRegionMultiTapStrategy
    public var model: TapRegionThresholdModel
    public var trainingMetrics: TapRegionQualificationMetrics

    public init(
        strategy: TapRegionMultiTapStrategy,
        model: TapRegionThresholdModel,
        trainingMetrics: TapRegionQualificationMetrics
    ) {
        self.strategy = strategy
        self.model = model
        self.trainingMetrics = trainingMetrics
    }
}

public struct TapRegionMultiTapStrategyResult: Equatable, Sendable {
    public var name: String
    public var trainingMetrics: TapRegionQualificationMetrics
    public var crossValidationMetrics: TapRegionQualificationMetrics
    public var selectedFeatures: [String: Int]

    public init(
        name: String,
        trainingMetrics: TapRegionQualificationMetrics,
        crossValidationMetrics: TapRegionQualificationMetrics,
        selectedFeatures: [String: Int]
    ) {
        self.name = name
        self.trainingMetrics = trainingMetrics
        self.crossValidationMetrics = crossValidationMetrics
        self.selectedFeatures = selectedFeatures
    }
}

public enum TapRegionMultiTapAnalysisError: Error, CustomStringConvertible {
    case missingLabels
    case malformedLabel(String)
    case incompleteGesture(
        side: TapRegionProbeSide,
        pattern: TapRegionMultiTapPattern,
        repetition: Int,
        expected: Int,
        actual: Int
    )
    case insufficientRepetitions

    public var description: String {
        switch self {
        case .missingLabels:
            return "capture has no auto-detected multi-tap labels"
        case .malformedLabel(let value):
            return "malformed multi-tap label: \(value)"
        case .incompleteGesture(
            let side,
            let pattern,
            let repetition,
            let expected,
            let actual
        ):
            return "\(side.rawValue) \(pattern.rawValue) repetition " +
                "\(repetition) has \(actual) members; expected \(expected)"
        case .insufficientRepetitions:
            return "multi-tap screening needs at least two repetitions"
        }
    }
}

public enum TapRegionMultiTapProbeAnalyzer {
    private static let candidateFeatureNames = [
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

    private struct GestureKey: Hashable {
        var side: TapRegionProbeSide
        var pattern: TapRegionMultiTapPattern
        var repetition: Int
    }

    private struct IndexedMember {
        var index: Int
        var observation: TapRegionProbeObservation
    }

    private struct VoteFit {
        var model: TapRegionThresholdModel
        var metrics: TapRegionQualificationMetrics
    }

    public static func gestures(
        from reader: CaptureReader
    ) throws -> [TapRegionMultiTapGesture] {
        let labels = try reader.labels().filter {
            $0.notes.hasPrefix("auto-detected multi-tap")
        }
        guard !labels.isEmpty else {
            throw TapRegionMultiTapAnalysisError.missingLabels
        }
        let allLabels = try reader.labels().filter {
            $0.label.hasPrefix("palm-")
        }
        let allObservations = try TapRegionProbeAnalyzer.observations(
            from: reader
        )
        guard allLabels.count == allObservations.count else {
            throw TapRegionMultiTapAnalysisError.malformedLabel(
                "label/observation count mismatch"
            )
        }

        var grouped: [GestureKey: [IndexedMember]] = [:]
        for (label, observation) in zip(allLabels, allObservations)
        where label.notes.hasPrefix("auto-detected multi-tap") {
            guard let patternValue = noteValue("pattern", in: label.notes),
                  let pattern = TapRegionMultiTapPattern(
                    rawValue: patternValue
                  ),
                  let memberValue = noteValue("member", in: label.notes),
                  let memberIndex = memberValue.split(separator: "/")
                    .first.flatMap({ Int($0) }) else {
                throw TapRegionMultiTapAnalysisError.malformedLabel(label.notes)
            }
            let key = GestureKey(
                side: observation.side,
                pattern: pattern,
                repetition: observation.repetition
            )
            grouped[key, default: []].append(IndexedMember(
                index: memberIndex,
                observation: observation
            ))
        }

        return try grouped.map { key, indexedMembers in
            let sorted = indexedMembers.sorted { $0.index < $1.index }
            guard sorted.count == key.pattern.memberCount else {
                throw TapRegionMultiTapAnalysisError.incompleteGesture(
                    side: key.side,
                    pattern: key.pattern,
                    repetition: key.repetition,
                    expected: key.pattern.memberCount,
                    actual: sorted.count
                )
            }
            return TapRegionMultiTapGesture(
                side: key.side,
                pattern: key.pattern,
                repetition: key.repetition,
                members: sorted.map(\.observation)
            )
        }.sorted {
            ($0.members.first?.peakTimestamp ?? 0) <
                ($1.members.first?.peakTimestamp ?? 0)
        }
    }

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
            if score($0.crossValidationMetrics) !=
                score($1.crossValidationMetrics) {
                return !score($0.crossValidationMetrics)
                    .lexicographicallyPrecedes(
                        score($1.crossValidationMetrics)
                    )
            }
            return $0.name < $1.name
        }
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

    private static func bestVoteFit(
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
            if score($0.metrics) != score($1.metrics) {
                return !score($0.metrics).lexicographicallyPrecedes(
                    score($1.metrics)
                )
            }
            return $0.model.featureName < $1.model.featureName
        }).first else {
            throw TapRegionProbeAnalysisError.insufficientObservations
        }
        return best
    }

    private static func prediction(
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

    private static func noteValue(
        _ key: String,
        in notes: String
    ) -> String? {
        notes.split(separator: ";").map {
            $0.trimmingCharacters(in: .whitespaces)
        }.first {
            $0.hasPrefix("\(key)=")
        }.map {
            String($0.dropFirst(key.count + 1))
        }
    }

    private static func score(
        _ metrics: TapRegionQualificationMetrics
    ) -> [Double] {
        [
            metrics.qualifies ? 1 : 0,
            metrics.minimumGroupCoverage,
            min(metrics.leftPrecision, metrics.rightPrecision),
            metrics.classifiedFraction,
            -Double(metrics.incorrect)
        ]
    }
}
