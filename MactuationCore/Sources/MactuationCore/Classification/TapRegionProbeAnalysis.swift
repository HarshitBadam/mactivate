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
    public static let modelFeatureNames: [String] = {
        var names = [
            "accel_peak_g",
            "accel_x_impulse_25_mg_s",
            "accel_y_impulse_25_mg_s",
            "accel_z_impulse_25_mg_s"
        ]
        for axis in ["x", "y", "z"] {
            names += [
                "gyro_\(axis)_impulse_10_deg",
                "gyro_\(axis)_impulse_25_deg",
                "gyro_\(axis)_impulse_50_deg",
                "gyro_\(axis)_peak_deg_s",
                "gyro_\(axis)_at_accel_peak_deg_s",
                "gyro_\(axis)_pre_impulse_10_deg",
                "gyro_\(axis)_post_impulse_10_deg",
                "gyro_\(axis)_post_impulse_25_deg",
                "gyro_\(axis)_post_impulse_50_deg",
                "gyro_\(axis)_peak_balance_deg_s",
                "gyro_\(axis)_post_pre_delta_25_deg",
                "gyro_\(axis)_signed_energy_fraction_50",
                "gyro_\(axis)_signed_extremum_delay_ms"
            ]
        }
        return names
    }()

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

public enum TapRegionProbeAnalyzer {
    private struct Vector3 {
        var x: Double
        var y: Double
        var z: Double

        static let zero = Vector3(x: 0, y: 0, z: 0)

        static func - (lhs: Vector3, rhs: Vector3) -> Vector3 {
            Vector3(x: lhs.x - rhs.x, y: lhs.y - rhs.y, z: lhs.z - rhs.z)
        }

        static func + (lhs: Vector3, rhs: Vector3) -> Vector3 {
            Vector3(x: lhs.x + rhs.x, y: lhs.y + rhs.y, z: lhs.z + rhs.z)
        }

        static func * (lhs: Vector3, rhs: Double) -> Vector3 {
            Vector3(x: lhs.x * rhs, y: lhs.y * rhs, z: lhs.z * rhs)
        }

        var magnitude: Double {
            (x * x + y * y + z * z).squareRoot()
        }
    }

    public static func observations(
        from reader: CaptureReader
    ) throws -> [TapRegionProbeObservation] {
        let accelerometer = try imuSamples(
            reader: reader,
            path: .spuAccelerometer
        )
        let gyroscope = try imuSamples(
            reader: reader,
            path: .spuGyroscope
        )
        let labels = try reader.labels().filter {
            $0.label.hasPrefix("palm-")
        }
        guard !labels.isEmpty else {
            throw TapRegionProbeAnalysisError.missingLabels
        }

        return try labels.map { label in
            let side = try side(from: label.label)
            guard let intensity = TapRegionProbeIntensity(
                rawValue: label.intensity
            ) else {
                throw TapRegionProbeAnalysisError.invalidLabel(
                    "\(label.label)/\(label.intensity)"
                )
            }
            let accelBaseline = mean(
                accelerometer,
                from: max(0, label.start - 0.25),
                through: max(0, label.start - 0.02)
            )
            let expectedDetectedPeak = label.notes.hasPrefix("auto-detected")
                ? label.start + 0.15
                : nil
            let peakCandidates = accelerometer.filter {
                if let expectedDetectedPeak {
                    return abs($0.timestamp - expectedDetectedPeak) <= 0.04
                }
                return $0.timestamp >= label.start && $0.timestamp <= label.end
            }
            guard let peak = peakCandidates.max(by: {
                (vector($0) - accelBaseline).magnitude <
                    (vector($1) - accelBaseline).magnitude
            }) else {
                throw TapRegionProbeAnalysisError.noSamples(
                    label: label.label,
                    path: .spuAccelerometer
                )
            }
            guard gyroscope.contains(where: {
                abs($0.timestamp - peak.timestamp) <= 0.05
            }) else {
                throw TapRegionProbeAnalysisError.noSamples(
                    label: label.label,
                    path: .spuGyroscope
                )
            }

            let gyroBaseline = mean(
                gyroscope,
                from: max(0, peak.timestamp - 0.25),
                through: max(0, peak.timestamp - 0.08)
            )
            let accelDelta = vector(peak) - accelBaseline
            let accelImpulse = integral(
                accelerometer,
                center: peak.timestamp,
                halfWindow: 0.025,
                baseline: accelBaseline
            ) * 1000
            let gyro10 = integral(
                gyroscope,
                center: peak.timestamp,
                halfWindow: 0.010,
                baseline: gyroBaseline
            )
            let gyro25 = integral(
                gyroscope,
                center: peak.timestamp,
                halfWindow: 0.025,
                baseline: gyroBaseline
            )
            let gyro50 = integral(
                gyroscope,
                center: peak.timestamp,
                halfWindow: 0.050,
                baseline: gyroBaseline
            )
            let gyroPeak = signedPeak(
                gyroscope,
                center: peak.timestamp,
                halfWindow: 0.050,
                baseline: gyroBaseline
            )
            let gyroAtPeak = valueNearest(
                gyroscope,
                timestamp: peak.timestamp,
                baseline: gyroBaseline
            )
            let gyroPre10 = integral(
                gyroscope,
                from: peak.timestamp - 0.010,
                through: peak.timestamp,
                baseline: gyroBaseline
            )
            let gyroPost10 = integral(
                gyroscope,
                from: peak.timestamp,
                through: peak.timestamp + 0.010,
                baseline: gyroBaseline
            )
            let gyroPre25 = integral(
                gyroscope,
                from: peak.timestamp - 0.025,
                through: peak.timestamp,
                baseline: gyroBaseline
            )
            let gyroPost25 = integral(
                gyroscope,
                from: peak.timestamp,
                through: peak.timestamp + 0.025,
                baseline: gyroBaseline
            )
            let gyroPost50 = integral(
                gyroscope,
                from: peak.timestamp,
                through: peak.timestamp + 0.050,
                baseline: gyroBaseline
            )
            let gyroExtrema = extrema(
                gyroscope,
                center: peak.timestamp,
                halfWindow: 0.050,
                baseline: gyroBaseline
            )
            let gyroEnergy = signedEnergyFractions(
                gyroscope,
                center: peak.timestamp,
                halfWindow: 0.050,
                baseline: gyroBaseline,
                signedBy: gyroPeak
            )
            let gyroDelay = signedExtremumDelays(
                gyroscope,
                center: peak.timestamp,
                halfWindow: 0.050,
                baseline: gyroBaseline
            )
            var features: [String: Double] = [
                "accel_peak_g": accelDelta.magnitude,
                "accel_x_impulse_25_mg_s": accelImpulse.x,
                "accel_y_impulse_25_mg_s": accelImpulse.y,
                "accel_z_impulse_25_mg_s": accelImpulse.z,
                "label_start_to_peak_s": peak.timestamp - label.start
            ]
            let axes: [(String, (Vector3) -> Double)] = [
                ("x", { $0.x }),
                ("y", { $0.y }),
                ("z", { $0.z })
            ]
            for (axis, component) in axes {
                features["gyro_\(axis)_impulse_10_deg"] = component(gyro10)
                features["gyro_\(axis)_impulse_25_deg"] = component(gyro25)
                features["gyro_\(axis)_impulse_50_deg"] = component(gyro50)
                features["gyro_\(axis)_peak_deg_s"] = component(gyroPeak)
                features["gyro_\(axis)_at_accel_peak_deg_s"] =
                    component(gyroAtPeak)
                features["gyro_\(axis)_pre_impulse_10_deg"] =
                    component(gyroPre10)
                features["gyro_\(axis)_post_impulse_10_deg"] =
                    component(gyroPost10)
                features["gyro_\(axis)_post_impulse_25_deg"] =
                    component(gyroPost25)
                features["gyro_\(axis)_post_impulse_50_deg"] =
                    component(gyroPost50)
                features["gyro_\(axis)_peak_balance_deg_s"] =
                    component(gyroExtrema.maximum) +
                    component(gyroExtrema.minimum)
                features["gyro_\(axis)_post_pre_delta_25_deg"] =
                    component(gyroPost25) - component(gyroPre25)
                features["gyro_\(axis)_signed_energy_fraction_50"] =
                    component(gyroEnergy)
                features["gyro_\(axis)_signed_extremum_delay_ms"] =
                    component(gyroDelay)
            }
            return TapRegionProbeObservation(
                side: side,
                intensity: intensity,
                repetition: label.repetition,
                peakTimestamp: peak.timestamp,
                features: features
            )
        }
    }

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
            metrics: metrics(for: evaluated),
            foldModels: models
        )
    }

    public static func evaluate(
        _ model: TapRegionThresholdModel,
        observations: [TapRegionProbeObservation]
    ) -> TapRegionQualificationMetrics {
        metrics(for: observations.map {
            ($0, model.predict($0))
        })
    }

    public static func evaluate(
        predictions: [TapRegionProbePrediction],
        observations: [TapRegionProbeObservation]
    ) -> TapRegionQualificationMetrics {
        guard predictions.count == observations.count else {
            return TapRegionQualificationMetrics(
                total: observations.count,
                correct: 0,
                incorrect: 0,
                ambiguous: observations.count,
                leftPrecision: 0,
                rightPrecision: 0,
                groupCoverage: [:]
            )
        }
        return metrics(for: Array(zip(observations, predictions)))
    }

    private static func metrics(
        for evaluated: [(
            TapRegionProbeObservation,
            TapRegionProbePrediction
        )]
    ) -> TapRegionQualificationMetrics {
        var correct = 0
        var incorrect = 0
        var ambiguous = 0
        var predictedLeft = 0
        var predictedRight = 0
        var correctLeft = 0
        var correctRight = 0
        var totals: [String: Int] = [:]
        var groupCorrect: [String: Int] = [:]
        for side in TapRegionProbeSide.allCases {
            for intensity in TapRegionProbeIntensity.allCases {
                totals[groupKey(side: side, intensity: intensity)] = 0
            }
        }

        for (observation, prediction) in evaluated {
            let key = groupKey(
                side: observation.side,
                intensity: observation.intensity
            )
            totals[key, default: 0] += 1
            switch prediction {
            case .ambiguous:
                ambiguous += 1
            case .left:
                predictedLeft += 1
                if observation.side == .left {
                    correct += 1
                    correctLeft += 1
                    groupCorrect[key, default: 0] += 1
                } else {
                    incorrect += 1
                }
            case .right:
                predictedRight += 1
                if observation.side == .right {
                    correct += 1
                    correctRight += 1
                    groupCorrect[key, default: 0] += 1
                } else {
                    incorrect += 1
                }
            }
        }

        let coverage = Dictionary(
            uniqueKeysWithValues: totals.map { key, count in
                (key, count == 0 ? 0 :
                    Double(groupCorrect[key, default: 0]) / Double(count))
            }
        )
        return TapRegionQualificationMetrics(
            total: evaluated.count,
            correct: correct,
            incorrect: incorrect,
            ambiguous: ambiguous,
            leftPrecision: predictedLeft == 0 ? 0 :
                Double(correctLeft) / Double(predictedLeft),
            rightPrecision: predictedRight == 0 ? 0 :
                Double(correctRight) / Double(predictedRight),
            groupCoverage: coverage
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

    private static func imuSamples(
        reader: CaptureReader,
        path: SensorPath
    ) throws -> [IMUSample] {
        let values: [IMUSample] = try reader.samples(for: path).compactMap {
            guard case .imu(_, let sample) = $0 else { return nil }
            return sample
        }
        guard !values.isEmpty else {
            throw TapRegionProbeAnalysisError.missingSensor(path)
        }
        return values
    }

    private static func side(from label: String) throws -> TapRegionProbeSide {
        switch label {
        case "palm-left": return .left
        case "palm-right": return .right
        default: throw TapRegionProbeAnalysisError.invalidLabel(label)
        }
    }

    private static func vector(_ sample: IMUSample) -> Vector3 {
        Vector3(x: sample.x, y: sample.y, z: sample.z)
    }

    private static func mean(
        _ samples: [IMUSample],
        from start: SensorTimestamp,
        through end: SensorTimestamp
    ) -> Vector3 {
        let selected = samples.filter {
            $0.timestamp >= start && $0.timestamp <= end
        }
        guard !selected.isEmpty else { return .zero }
        let sum = selected.reduce(Vector3.zero) {
            $0 + vector($1)
        }
        return sum * (1 / Double(selected.count))
    }

    private static func integral(
        _ samples: [IMUSample],
        center: SensorTimestamp,
        halfWindow: Double,
        baseline: Vector3
    ) -> Vector3 {
        integral(
            samples,
            from: center - halfWindow,
            through: center + halfWindow,
            baseline: baseline
        )
    }

    private static func integral(
        _ samples: [IMUSample],
        from start: SensorTimestamp,
        through end: SensorTimestamp,
        baseline: Vector3
    ) -> Vector3 {
        let selected = samples.filter {
            $0.timestamp >= start && $0.timestamp <= end
        }
        guard selected.count >= 2 else { return .zero }
        var result = Vector3.zero
        for (previous, current) in zip(selected, selected.dropFirst()) {
            let dt = current.timestamp - previous.timestamp
            guard dt > 0 else { continue }
            let previousValue = vector(previous) - baseline
            let currentValue = vector(current) - baseline
            result = result + (previousValue + currentValue) * (dt / 2)
        }
        return result
    }

    private static func valueNearest(
        _ samples: [IMUSample],
        timestamp: SensorTimestamp,
        baseline: Vector3
    ) -> Vector3 {
        guard let sample = samples.min(by: {
            abs($0.timestamp - timestamp) < abs($1.timestamp - timestamp)
        }) else {
            return .zero
        }
        return vector(sample) - baseline
    }

    private static func extrema(
        _ samples: [IMUSample],
        center: SensorTimestamp,
        halfWindow: Double,
        baseline: Vector3
    ) -> (minimum: Vector3, maximum: Vector3) {
        let values = samples.filter {
            $0.timestamp >= center - halfWindow &&
                $0.timestamp <= center + halfWindow
        }.map {
            vector($0) - baseline
        }
        return (
            minimum: Vector3(
                x: values.map(\.x).min() ?? 0,
                y: values.map(\.y).min() ?? 0,
                z: values.map(\.z).min() ?? 0
            ),
            maximum: Vector3(
                x: values.map(\.x).max() ?? 0,
                y: values.map(\.y).max() ?? 0,
                z: values.map(\.z).max() ?? 0
            )
        )
    }

    private static func signedEnergyFractions(
        _ samples: [IMUSample],
        center: SensorTimestamp,
        halfWindow: Double,
        baseline: Vector3,
        signedBy peak: Vector3
    ) -> Vector3 {
        let values = samples.filter {
            $0.timestamp >= center - halfWindow &&
                $0.timestamp <= center + halfWindow
        }.map {
            vector($0) - baseline
        }
        let xEnergy = values.reduce(0) { $0 + $1.x * $1.x }
        let yEnergy = values.reduce(0) { $0 + $1.y * $1.y }
        let zEnergy = values.reduce(0) { $0 + $1.z * $1.z }
        let total = xEnergy + yEnergy + zEnergy
        guard total > 0 else { return .zero }
        return Vector3(
            x: copysign(xEnergy / total, peak.x),
            y: copysign(yEnergy / total, peak.y),
            z: copysign(zEnergy / total, peak.z)
        )
    }

    private static func signedExtremumDelays(
        _ samples: [IMUSample],
        center: SensorTimestamp,
        halfWindow: Double,
        baseline: Vector3
    ) -> Vector3 {
        let values = samples.filter {
            $0.timestamp >= center - halfWindow &&
                $0.timestamp <= center + halfWindow
        }
        func delay(_ component: (Vector3) -> Double) -> Double {
            guard let sample = values.max(by: {
                abs(component(vector($0) - baseline)) <
                    abs(component(vector($1) - baseline))
            }) else {
                return 0
            }
            let value = component(vector(sample) - baseline)
            return (sample.timestamp - center) * 1_000 *
                (value < 0 ? -1 : 1)
        }
        return Vector3(
            x: delay { $0.x },
            y: delay { $0.y },
            z: delay { $0.z }
        )
    }

    private static func signedPeak(
        _ samples: [IMUSample],
        center: SensorTimestamp,
        halfWindow: Double,
        baseline: Vector3
    ) -> Vector3 {
        let values = samples.filter {
            $0.timestamp >= center - halfWindow &&
                $0.timestamp <= center + halfWindow
        }.map {
            vector($0) - baseline
        }
        return Vector3(
            x: values.max(by: { abs($0.x) < abs($1.x) })?.x ?? 0,
            y: values.max(by: { abs($0.y) < abs($1.y) })?.y ?? 0,
            z: values.max(by: { abs($0.z) < abs($1.z) })?.z ?? 0
        )
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
        let candidateScore = score(candidate)
        let currentScore = score(current)
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

    private static func score(_ fit: TapRegionThresholdFit) -> [Double] {
        [
            fit.metrics.qualifies ? 1 : 0,
            fit.metrics.minimumGroupCoverage,
            min(fit.metrics.leftPrecision, fit.metrics.rightPrecision),
            fit.metrics.classifiedFraction,
            -Double(fit.metrics.incorrect)
        ]
    }

    private static func groupKey(
        side: TapRegionProbeSide,
        intensity: TapRegionProbeIntensity
    ) -> String {
        "\(side.rawValue)-\(intensity.rawValue)"
    }
}
