import Foundation

public typealias TapRegionProbeSide = TapRegionSide

public enum TapRegionProbeIntensity: String, Codable, CaseIterable, Hashable, Sendable {
    case comfort
    case firm
}

public enum TapRegionProbePrediction: String, Equatable, Sendable {
    case left
    case right
    case ambiguous
}

public struct TapRegionProbeObservation: Equatable, Sendable {
    public var side: TapRegionProbeSide
    public var intensity: TapRegionProbeIntensity
    public var repetition: Int
    public var peakTimestamp: SensorTimestamp
    public var features: [String: Double]

    public init(
        side: TapRegionProbeSide,
        intensity: TapRegionProbeIntensity,
        repetition: Int,
        peakTimestamp: SensorTimestamp,
        features: [String: Double]
    ) {
        self.side = side
        self.intensity = intensity
        self.repetition = repetition
        self.peakTimestamp = peakTimestamp
        self.features = features
    }
}

public struct TapRegionQualificationMetrics: Equatable, Sendable {
    public var total: Int
    public var correct: Int
    public var incorrect: Int
    public var ambiguous: Int
    public var leftPrecision: Double
    public var rightPrecision: Double
    public var groupCoverage: [String: Double]

    public init(
        total: Int,
        correct: Int,
        incorrect: Int,
        ambiguous: Int,
        leftPrecision: Double,
        rightPrecision: Double,
        groupCoverage: [String: Double]
    ) {
        self.total = total
        self.correct = correct
        self.incorrect = incorrect
        self.ambiguous = ambiguous
        self.leftPrecision = leftPrecision
        self.rightPrecision = rightPrecision
        self.groupCoverage = groupCoverage
    }

    public var minimumGroupCoverage: Double {
        groupCoverage.values.min() ?? 0
    }

    public var classifiedFraction: Double {
        guard total > 0 else { return 0 }
        return Double(correct + incorrect) / Double(total)
    }

    public var qualifies: Bool {
        leftPrecision >= 0.95 &&
            rightPrecision >= 0.95 &&
            minimumGroupCoverage >= 0.90
    }
}
