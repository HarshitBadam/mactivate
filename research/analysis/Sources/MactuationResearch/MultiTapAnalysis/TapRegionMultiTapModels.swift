import Foundation
import MactuationCore

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
