import Foundation
import MactuationCore

public struct TapRegionLinearModel: Equatable, Sendable {
    public var name: String
    public var featureNames: [String]
    public var centers: [Double]
    public var scales: [Double]
    public var weights: [Double]
    public var intercept: Double
    public var lowerBoundary: Double
    public var upperBoundary: Double
    public var lowerSide: TapRegionProbeSide

    public init(
        name: String,
        featureNames: [String],
        centers: [Double],
        scales: [Double],
        weights: [Double],
        intercept: Double,
        lowerBoundary: Double,
        upperBoundary: Double,
        lowerSide: TapRegionProbeSide
    ) {
        self.name = name
        self.featureNames = featureNames
        self.centers = centers
        self.scales = scales
        self.weights = weights
        self.intercept = intercept
        self.lowerBoundary = lowerBoundary
        self.upperBoundary = upperBoundary
        self.lowerSide = lowerSide
    }

    public func score(_ observation: TapRegionProbeObservation) -> Double? {
        guard featureNames.count == centers.count,
              centers.count == scales.count,
              scales.count == weights.count else {
            return nil
        }
        var result = intercept
        for index in featureNames.indices {
            guard let value = observation.features[featureNames[index]],
                  scales[index] > 0 else {
                return nil
            }
            result += ((value - centers[index]) / scales[index]) *
                weights[index]
        }
        return result
    }

    public func predict(_ observation: TapRegionProbeObservation)
        -> TapRegionProbePrediction {
        guard let score = score(observation) else { return .ambiguous }
        if score < lowerBoundary {
            return lowerSide == .left ? .left : .right
        }
        if score > upperBoundary {
            return lowerSide == .left ? .right : .left
        }
        return .ambiguous
    }
}

public struct TapRegionLinearFit: Equatable, Sendable {
    public var model: TapRegionLinearModel
    public var metrics: TapRegionQualificationMetrics

    public init(
        model: TapRegionLinearModel,
        metrics: TapRegionQualificationMetrics
    ) {
        self.model = model
        self.metrics = metrics
    }
}

public struct TapRegionLinearCrossValidationResult: Equatable, Sendable {
    public var metrics: TapRegionQualificationMetrics
    public var foldModels: [TapRegionLinearModel]

    public init(
        metrics: TapRegionQualificationMetrics,
        foldModels: [TapRegionLinearModel]
    ) {
        self.metrics = metrics
        self.foldModels = foldModels
    }
}
