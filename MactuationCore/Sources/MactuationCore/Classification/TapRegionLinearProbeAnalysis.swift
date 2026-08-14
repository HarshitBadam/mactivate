import Foundation

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

    private static func fit(
        _ observations: [TapRegionProbeObservation],
        name: String,
        featureNames: [String],
        ridge: Double
    ) throws -> TapRegionLinearFit {
        guard !observations.isEmpty, !featureNames.isEmpty else {
            throw TapRegionProbeAnalysisError.insufficientObservations
        }
        let rawRows: [[Double]] = try observations.map { observation in
            try featureNames.map { feature in
                guard let value = observation.features[feature],
                      value.isFinite else {
                    throw TapRegionProbeAnalysisError.insufficientObservations
                }
                return value
            }
        }
        let columnCount = featureNames.count
        let centers = (0..<columnCount).map { column in
            rawRows.reduce(0) { $0 + $1[column] } / Double(rawRows.count)
        }
        let scales = (0..<columnCount).map { column in
            let variance = rawRows.reduce(0) {
                let delta = $1[column] - centers[column]
                return $0 + delta * delta
            } / Double(rawRows.count)
            return max(variance.squareRoot(), 1e-9)
        }
        let rows = rawRows.map { row in
            row.indices.map {
                (row[$0] - centers[$0]) / scales[$0]
            }
        }
        let leftIndices = observations.indices.filter {
            observations[$0].side == .left
        }
        let rightIndices = observations.indices.filter {
            observations[$0].side == .right
        }
        guard !leftIndices.isEmpty, !rightIndices.isEmpty else {
            throw TapRegionProbeAnalysisError.insufficientObservations
        }
        let leftMean = mean(rows, indices: leftIndices)
        let rightMean = mean(rows, indices: rightIndices)
        var covariance = Array(
            repeating: Array(repeating: 0.0, count: columnCount),
            count: columnCount
        )
        for index in rows.indices {
            let classMean = observations[index].side == .left
                ? leftMean : rightMean
            let delta = rows[index].indices.map {
                rows[index][$0] - classMean[$0]
            }
            for row in 0..<columnCount {
                for column in 0..<columnCount {
                    covariance[row][column] += delta[row] * delta[column]
                }
            }
        }
        let divisor = Double(max(1, rows.count - 2))
        for row in 0..<columnCount {
            for column in 0..<columnCount {
                covariance[row][column] /= divisor
            }
            covariance[row][row] += ridge
        }
        guard let inverse = invert(covariance) else {
            throw TapRegionProbeAnalysisError.insufficientObservations
        }
        let meanDifference = zip(rightMean, leftMean).map(-)
        let weights = multiply(inverse, by: meanDifference)
        let leftProjected = dot(leftMean, multiply(inverse, by: leftMean))
        let rightProjected = dot(rightMean, multiply(inverse, by: rightMean))
        let intercept = -0.5 * (rightProjected - leftProjected)

        var provisional = TapRegionLinearModel(
            name: name,
            featureNames: featureNames,
            centers: centers,
            scales: scales,
            weights: weights,
            intercept: intercept,
            lowerBoundary: 0,
            upperBoundary: 0,
            lowerSide: .left
        )
        let scored = try observations.map { observation -> TapRegionProbeObservation in
            guard let score = provisional.score(observation) else {
                throw TapRegionProbeAnalysisError.insufficientObservations
            }
            var copy = observation
            copy.features = ["linear_score": score]
            return copy
        }
        let threshold = try TapRegionProbeAnalyzer.fitThreshold(
            featureName: "linear_score",
            observations: scored
        )
        provisional.lowerBoundary = threshold.model.lowerBoundary
        provisional.upperBoundary = threshold.model.upperBoundary
        provisional.lowerSide = threshold.model.lowerSide
        let metrics = TapRegionProbeAnalyzer.evaluate(
            predictions: observations.map { provisional.predict($0) },
            observations: observations
        )
        return TapRegionLinearFit(model: provisional, metrics: metrics)
    }

    private static func axes(_ format: String) -> [String] {
        ["x", "y", "z"].map { String(format: format, $0) }
    }

    private static func mean(
        _ rows: [[Double]],
        indices: [Int]
    ) -> [Double] {
        guard let width = rows.first?.count else { return [] }
        var result = Array(repeating: 0.0, count: width)
        for index in indices {
            for column in 0..<width {
                result[column] += rows[index][column]
            }
        }
        return result.map { $0 / Double(indices.count) }
    }

    private static func multiply(
        _ matrix: [[Double]],
        by vector: [Double]
    ) -> [Double] {
        matrix.map { row in
            zip(row, vector).reduce(0) { $0 + $1.0 * $1.1 }
        }
    }

    private static func dot(_ lhs: [Double], _ rhs: [Double]) -> Double {
        zip(lhs, rhs).reduce(0) { $0 + $1.0 * $1.1 }
    }

    private static func invert(_ matrix: [[Double]]) -> [[Double]]? {
        let size = matrix.count
        guard size > 0, matrix.allSatisfy({ $0.count == size }) else {
            return nil
        }
        var augmented = matrix.enumerated().map { row, values in
            values + (0..<size).map { $0 == row ? 1.0 : 0.0 }
        }
        for pivot in 0..<size {
            guard let bestRow = (pivot..<size).max(by: {
                abs(augmented[$0][pivot]) < abs(augmented[$1][pivot])
            }), abs(augmented[bestRow][pivot]) > 1e-12 else {
                return nil
            }
            if bestRow != pivot {
                augmented.swapAt(bestRow, pivot)
            }
            let divisor = augmented[pivot][pivot]
            for column in 0..<(size * 2) {
                augmented[pivot][column] /= divisor
            }
            for row in 0..<size where row != pivot {
                let factor = augmented[row][pivot]
                guard factor != 0 else { continue }
                for column in 0..<(size * 2) {
                    augmented[row][column] -= factor *
                        augmented[pivot][column]
                }
            }
        }
        return augmented.map { Array($0[size..<(size * 2)]) }
    }

    private static func isBetter(
        _ candidate: TapRegionLinearFit,
        than current: TapRegionLinearFit
    ) -> Bool {
        let candidateScore = score(candidate.metrics)
        let currentScore = score(current.metrics)
        if candidateScore != currentScore {
            return !candidateScore.lexicographicallyPrecedes(currentScore)
        }
        return candidate.model.name < current.model.name
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
