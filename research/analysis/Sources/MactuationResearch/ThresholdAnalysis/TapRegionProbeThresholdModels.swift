import Foundation
import MactuationCore

public struct TapRegionThresholdModel: Equatable, Sendable {
    public var featureName: String
    public var lowerBoundary: Double
    public var upperBoundary: Double
    public var lowerSide: TapRegionProbeSide

    public init(
        featureName: String,
        lowerBoundary: Double,
        upperBoundary: Double,
        lowerSide: TapRegionProbeSide
    ) {
        self.featureName = featureName
        self.lowerBoundary = lowerBoundary
        self.upperBoundary = upperBoundary
        self.lowerSide = lowerSide
    }

    public func predict(_ observation: TapRegionProbeObservation)
        -> TapRegionProbePrediction {
        guard let value = observation.features[featureName] else {
            return .ambiguous
        }
        if value < lowerBoundary {
            return lowerSide == .left ? .left : .right
        }
        if value > upperBoundary {
            return lowerSide == .left ? .right : .left
        }
        return .ambiguous
    }
}

public struct TapRegionThresholdFit: Equatable, Sendable {
    public var model: TapRegionThresholdModel
    public var metrics: TapRegionQualificationMetrics

    public init(
        model: TapRegionThresholdModel,
        metrics: TapRegionQualificationMetrics
    ) {
        self.model = model
        self.metrics = metrics
    }
}

public struct TapRegionCrossValidationResult: Equatable, Sendable {
    public var metrics: TapRegionQualificationMetrics
    public var foldModels: [TapRegionThresholdModel]

    public init(
        metrics: TapRegionQualificationMetrics,
        foldModels: [TapRegionThresholdModel]
    ) {
        self.metrics = metrics
        self.foldModels = foldModels
    }
}

public enum TapRegionProbeAnalysisError: Error, CustomStringConvertible {
    case missingSensor(SensorPath)
    case missingLabels
    case invalidLabel(String)
    case noSamples(label: String, path: SensorPath)
    case insufficientObservations

    public var description: String {
        switch self {
        case .missingSensor(let path):
            return "capture has no \(path.rawValue) stream"
        case .missingLabels:
            return "capture has no labelled left/right tap windows"
        case .invalidLabel(let value):
            return "unsupported region label: \(value)"
        case .noSamples(let label, let path):
            return "\(label) contains no \(path.rawValue) samples"
        case .insufficientObservations:
            return "both sides and force levels need labelled observations"
        }
    }
}
