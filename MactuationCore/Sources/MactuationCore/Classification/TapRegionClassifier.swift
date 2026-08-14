import Foundation

public enum TapRegionSide: String, Codable, CaseIterable, Hashable, Sendable {
    case left
    case right

    public var opposite: TapRegionSide {
        self == .left ? .right : .left
    }
}

public enum TapRegionPrediction: String, Codable, Equatable, Sendable {
    case left
    case right
    case unknown

    public init(side: TapRegionSide) {
        self = side == .left ? .left : .right
    }

    public var side: TapRegionSide? {
        switch self {
        case .left: return .left
        case .right: return .right
        case .unknown: return nil
        }
    }
}

public enum TapRegionPattern: String, Codable, CaseIterable, Hashable, Sendable {
    case double
    case triple

    public var memberCount: Int {
        switch self {
        case .double: return 2
        case .triple: return 3
        }
    }
}

public enum TapRegionAggregationStrategy: String, Codable, Sendable {
    case medianMembers
}

public struct TapRegionCalibrationProfile: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public static let featureName = "gyro_x_peak_balance_deg_s"
    public static let featureVersion = "gyro-x-peak-balance-50ms-v1"

    public var schemaVersion: Int
    public var version: String
    public var feature: String
    public var featureVersion: String
    public var strategy: TapRegionAggregationStrategy
    public var lowerBoundary: Double
    public var upperBoundary: Double
    public var lowerSide: TapRegionSide
    public var samplesPerGesture: Int

    public init(
        schemaVersion: Int = currentSchemaVersion,
        version: String,
        feature: String = featureName,
        featureVersion: String = featureVersion,
        strategy: TapRegionAggregationStrategy = .medianMembers,
        lowerBoundary: Double,
        upperBoundary: Double,
        lowerSide: TapRegionSide,
        samplesPerGesture: Int
    ) {
        self.schemaVersion = schemaVersion
        self.version = version
        self.feature = feature
        self.featureVersion = featureVersion
        self.strategy = strategy
        self.lowerBoundary = lowerBoundary
        self.upperBoundary = upperBoundary
        self.lowerSide = lowerSide
        self.samplesPerGesture = samplesPerGesture
    }

    public var isValid: Bool {
        schemaVersion == Self.currentSchemaVersion &&
            version.hasPrefix("personal-region-") &&
            feature == Self.featureName &&
            featureVersion == Self.featureVersion &&
            lowerBoundary.isFinite &&
            upperBoundary.isFinite &&
            lowerBoundary < upperBoundary &&
            samplesPerGesture >= 5
    }

    public var deterministicDigest: String {
        var digest = StreamDigest()
        digest.update(string: String(schemaVersion))
        digest.update(string: version)
        digest.update(string: feature)
        digest.update(string: featureVersion)
        digest.update(string: strategy.rawValue)
        digest.update(string: String(lowerBoundary.bitPattern, radix: 16))
        digest.update(string: String(upperBoundary.bitPattern, radix: 16))
        digest.update(string: lowerSide.rawValue)
        digest.update(string: String(samplesPerGesture))
        return digest.value
    }

    public func predict(feature value: Double) -> TapRegionPrediction {
        guard isValid, value.isFinite else { return .unknown }
        if value < lowerBoundary {
            return TapRegionPrediction(side: lowerSide)
        }
        if value > upperBoundary {
            return TapRegionPrediction(side: lowerSide.opposite)
        }
        return .unknown
    }
}

public struct TapRegionCalibrationGesture: Equatable, Sendable {
    public var side: TapRegionSide
    public var pattern: TapRegionPattern
    public var repetition: Int
    public var memberFeatures: [Double]

    public init(
        side: TapRegionSide,
        pattern: TapRegionPattern,
        repetition: Int,
        memberFeatures: [Double]
    ) {
        self.side = side
        self.pattern = pattern
        self.repetition = repetition
        self.memberFeatures = memberFeatures
    }

    public var medianFeature: Double? {
        guard memberFeatures.count == pattern.memberCount,
              memberFeatures.allSatisfy(\.isFinite) else {
            return nil
        }
        let sorted = memberFeatures.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2
            : sorted[middle]
    }
}

public enum TapRegionCalibrationProfileError: Error, Equatable,
    CustomStringConvertible {
    case incomplete(side: TapRegionSide, pattern: TapRegionPattern, count: Int)
    case malformedGesture
    case overlappingDistributions
    case qualificationFailed(TapRegionQualificationMetrics)

    public var description: String {
        switch self {
        case .incomplete(let side, let pattern, let count):
            return "\(side.rawValue) \(pattern.rawValue) needs 5 gestures; " +
                "captured \(count)."
        case .malformedGesture:
            return "A calibration gesture did not contain the expected tap count."
        case .overlappingDistributions:
            return "Left and right calibration values overlap. Recalibrate with " +
                "short, consistent taps near the outer palm rests."
        case .qualificationFailed:
            return "Calibration did not meet the required precision and coverage."
        }
    }
}

public struct TapRegionCalibrationBuildResult: Equatable, Sendable {
    public var profile: TapRegionCalibrationProfile
    public var crossValidationMetrics: TapRegionQualificationMetrics

    public init(
        profile: TapRegionCalibrationProfile,
        crossValidationMetrics: TapRegionQualificationMetrics
    ) {
        self.profile = profile
        self.crossValidationMetrics = crossValidationMetrics
    }
}

public enum TapRegionCalibrationProfileBuilder {
    public static let requiredGesturesPerTarget = 5

    public static func build(
        gestures: [TapRegionCalibrationGesture],
        version: String = "personal-region-\(UUID().uuidString.lowercased())"
    ) throws -> TapRegionCalibrationBuildResult {
        try validateCoverage(gestures)
        let repetitions = Set(gestures.map(\.repetition)).sorted()
        guard repetitions.count >= requiredGesturesPerTarget else {
            throw TapRegionCalibrationProfileError.malformedGesture
        }

        var evaluatedObservations: [TapRegionProbeObservation] = []
        var evaluatedPredictions: [TapRegionProbePrediction] = []
        for heldOutRepetition in repetitions {
            let training = gestures.filter {
                $0.repetition != heldOutRepetition
            }
            let heldOut = gestures.filter {
                $0.repetition == heldOutRepetition
            }
            let profile = try makeProfile(
                gestures: training,
                version: version,
                minimumSamples: requiredGesturesPerTarget - 1
            )
            for gesture in heldOut {
                guard let value = gesture.medianFeature else {
                    throw TapRegionCalibrationProfileError.malformedGesture
                }
                evaluatedObservations.append(observation(
                    for: gesture,
                    value: value
                ))
                evaluatedPredictions.append(probePrediction(
                    calibrationPrediction(profile: profile, value: value)
                ))
            }
        }

        let metrics = TapRegionProbeAnalyzer.evaluate(
            predictions: evaluatedPredictions,
            observations: evaluatedObservations
        )
        guard metrics.qualifies else {
            throw TapRegionCalibrationProfileError.qualificationFailed(metrics)
        }
        return TapRegionCalibrationBuildResult(
            profile: try makeProfile(
                gestures: gestures,
                version: version,
                minimumSamples: requiredGesturesPerTarget
            ),
            crossValidationMetrics: metrics
        )
    }

    private static func validateCoverage(
        _ gestures: [TapRegionCalibrationGesture]
    ) throws {
        guard gestures.allSatisfy({ $0.medianFeature != nil }) else {
            throw TapRegionCalibrationProfileError.malformedGesture
        }
        for side in TapRegionSide.allCases {
            for pattern in TapRegionPattern.allCases {
                let count = gestures.filter {
                    $0.side == side && $0.pattern == pattern
                }.count
                guard count >= requiredGesturesPerTarget else {
                    throw TapRegionCalibrationProfileError.incomplete(
                        side: side,
                        pattern: pattern,
                        count: count
                    )
                }
            }
        }
    }

    private static func makeProfile(
        gestures: [TapRegionCalibrationGesture],
        version: String,
        minimumSamples: Int
    ) throws -> TapRegionCalibrationProfile {
        let left = gestures.filter { $0.side == .left }
            .compactMap(\.medianFeature)
        let right = gestures.filter { $0.side == .right }
            .compactMap(\.medianFeature)
        guard left.count >= minimumSamples * TapRegionPattern.allCases.count,
              right.count >= minimumSamples * TapRegionPattern.allCases.count,
              let leftMinimum = left.min(),
              let leftMaximum = left.max(),
              let rightMinimum = right.min(),
              let rightMaximum = right.max() else {
            throw TapRegionCalibrationProfileError.malformedGesture
        }

        let lowerSide: TapRegionSide
        let lowerMaximum: Double
        let upperMinimum: Double
        if leftMaximum < rightMinimum {
            lowerSide = .left
            lowerMaximum = leftMaximum
            upperMinimum = rightMinimum
        } else if rightMaximum < leftMinimum {
            lowerSide = .right
            lowerMaximum = rightMaximum
            upperMinimum = leftMinimum
        } else {
            throw TapRegionCalibrationProfileError.overlappingDistributions
        }
        let gap = upperMinimum - lowerMaximum
        return TapRegionCalibrationProfile(
            version: version,
            lowerBoundary: lowerMaximum + gap * 0.25,
            upperBoundary: upperMinimum - gap * 0.25,
            lowerSide: lowerSide,
            samplesPerGesture: minimumSamples
        )
    }

    private static func observation(
        for gesture: TapRegionCalibrationGesture,
        value: Double
    ) -> TapRegionProbeObservation {
        TapRegionProbeObservation(
            side: gesture.side,
            intensity: gesture.pattern == .double ? .comfort : .firm,
            repetition: gesture.repetition,
            peakTimestamp: 0,
            features: [TapRegionCalibrationProfile.featureName: value]
        )
    }

    private static func probePrediction(
        _ prediction: TapRegionPrediction
    ) -> TapRegionProbePrediction {
        switch prediction {
        case .left: return .left
        case .right: return .right
        case .unknown: return .ambiguous
        }
    }

    private static func calibrationPrediction(
        profile: TapRegionCalibrationProfile,
        value: Double
    ) -> TapRegionPrediction {
        if value < profile.lowerBoundary {
            return TapRegionPrediction(side: profile.lowerSide)
        }
        if value > profile.upperBoundary {
            return TapRegionPrediction(side: profile.lowerSide.opposite)
        }
        return .unknown
    }
}

public struct TapRegionFeatureExtractorConfiguration: Equatable, Sendable {
    public var baselineStartBeforePeakS: Double
    public var baselineEndBeforePeakS: Double
    public var extremumHalfWindowS: Double
    public var maximumSampleGapS: Double
    public var maximumInterSampleGapS: Double

    public init(
        baselineStartBeforePeakS: Double = 0.25,
        baselineEndBeforePeakS: Double = 0.08,
        extremumHalfWindowS: Double = 0.05,
        maximumSampleGapS: Double = 0.01,
        maximumInterSampleGapS: Double = 0.02
    ) {
        self.baselineStartBeforePeakS = baselineStartBeforePeakS
        self.baselineEndBeforePeakS = baselineEndBeforePeakS
        self.extremumHalfWindowS = extremumHalfWindowS
        self.maximumSampleGapS = maximumSampleGapS
        self.maximumInterSampleGapS = maximumInterSampleGapS
    }
}

public enum TapRegionFeatureExtractionError: Error, Equatable, Sendable {
    case insufficientBaseline
    case insufficientPostEventData
    case discontinuousGyroscopeData
    case missingPeakWindow
    case gyroTooFarFromPeak
    case nonFiniteFeature
}

public struct TapRegionMemberFeature: Equatable, Sendable {
    public var peakTimestamp: SensorTimestamp
    public var gyroXPeakBalanceDegS: Double

    public init(
        peakTimestamp: SensorTimestamp,
        gyroXPeakBalanceDegS: Double
    ) {
        self.peakTimestamp = peakTimestamp
        self.gyroXPeakBalanceDegS = gyroXPeakBalanceDegS
    }
}

public struct TapRegionFeatureExtractor: Sendable {
    public var configuration: TapRegionFeatureExtractorConfiguration

    public init(
        configuration: TapRegionFeatureExtractorConfiguration =
            TapRegionFeatureExtractorConfiguration()
    ) {
        self.configuration = configuration
    }

    public func extract(
        gyroscope samples: [IMUSample],
        peakTimestamp: SensorTimestamp
    ) throws -> TapRegionMemberFeature {
        let baseline = samples.filter {
            $0.timestamp >= peakTimestamp -
                configuration.baselineStartBeforePeakS &&
                $0.timestamp <= peakTimestamp -
                configuration.baselineEndBeforePeakS
        }
        guard !baseline.isEmpty else {
            throw TapRegionFeatureExtractionError.insufficientBaseline
        }
        guard hasContinuousCoverage(
            baseline,
            from: peakTimestamp -
                configuration.baselineStartBeforePeakS,
            through: peakTimestamp -
                configuration.baselineEndBeforePeakS
        ) else {
            throw TapRegionFeatureExtractionError.discontinuousGyroscopeData
        }
        guard let latest = samples.last?.timestamp,
              latest >= peakTimestamp +
                configuration.extremumHalfWindowS -
                configuration.maximumSampleGapS else {
            throw TapRegionFeatureExtractionError.insufficientPostEventData
        }
        let window = samples.filter {
            abs($0.timestamp - peakTimestamp) <=
                configuration.extremumHalfWindowS
        }
        guard !window.isEmpty else {
            throw TapRegionFeatureExtractionError.missingPeakWindow
        }
        guard hasContinuousCoverage(
            window,
            from: peakTimestamp - configuration.extremumHalfWindowS,
            through: peakTimestamp + configuration.extremumHalfWindowS
        ) else {
            throw TapRegionFeatureExtractionError.discontinuousGyroscopeData
        }
        guard let nearest = window.min(by: {
            abs($0.timestamp - peakTimestamp) <
                abs($1.timestamp - peakTimestamp)
        }), abs(nearest.timestamp - peakTimestamp) <=
            configuration.maximumSampleGapS else {
            throw TapRegionFeatureExtractionError.gyroTooFarFromPeak
        }
        let baselineX = baseline.reduce(0) { $0 + $1.x } /
            Double(baseline.count)
        let values = window.map { $0.x - baselineX }
        guard let minimum = values.min(),
              let maximum = values.max() else {
            throw TapRegionFeatureExtractionError.missingPeakWindow
        }
        let feature = minimum + maximum
        guard feature.isFinite else {
            throw TapRegionFeatureExtractionError.nonFiniteFeature
        }
        return TapRegionMemberFeature(
            peakTimestamp: peakTimestamp,
            gyroXPeakBalanceDegS: feature
        )
    }

    private func hasContinuousCoverage(
        _ samples: [IMUSample],
        from start: SensorTimestamp,
        through end: SensorTimestamp
    ) -> Bool {
        guard let first = samples.first?.timestamp,
              let last = samples.last?.timestamp,
              first <= start + configuration.maximumInterSampleGapS,
              last >= end - configuration.maximumInterSampleGapS else {
            return false
        }
        return zip(samples, samples.dropFirst()).allSatisfy {
            $1.timestamp - $0.timestamp <=
                configuration.maximumInterSampleGapS
        }
    }
}

public enum TapRegionResolutionReason: String, Codable, Equatable, Sendable {
    case resolved
    case unsupportedTapCount
    case invalidProfile
    case insufficientGyroscopeData
    case ambiguous
}

public struct TapRegionClassification: Equatable, Sendable {
    public var prediction: TapRegionPrediction
    public var reason: TapRegionResolutionReason
    public var memberFeatures: [TapRegionMemberFeature]
    public var aggregatedFeature: Double?
    public var profileVersion: String?

    public init(
        prediction: TapRegionPrediction,
        reason: TapRegionResolutionReason,
        memberFeatures: [TapRegionMemberFeature] = [],
        aggregatedFeature: Double? = nil,
        profileVersion: String? = nil
    ) {
        self.prediction = prediction
        self.reason = reason
        self.memberFeatures = memberFeatures
        self.aggregatedFeature = aggregatedFeature
        self.profileVersion = profileVersion
    }
}

public enum TapRegionStreamError: Error, Equatable {
    case invalidBufferDuration
    case nonMonotonicTimestamp(previous: SensorTimestamp, current: SensorTimestamp)
}

public final class TapRegionStreamClassifier {
    public let bufferDurationS: Double
    public let extractor: TapRegionFeatureExtractor

    private var gyroscopeSamples: [IMUSample] = []
    private var lastGyroscopeTimestamp: SensorTimestamp?

    public init(
        bufferDurationS: Double = 5,
        extractor: TapRegionFeatureExtractor = TapRegionFeatureExtractor()
    ) throws {
        guard bufferDurationS.isFinite,
              bufferDurationS >=
                extractor.configuration.baselineStartBeforePeakS +
                extractor.configuration.extremumHalfWindowS else {
            throw TapRegionStreamError.invalidBufferDuration
        }
        self.bufferDurationS = bufferDurationS
        self.extractor = extractor
    }

    public var bufferedGyroscopeSampleCount: Int {
        gyroscopeSamples.count
    }

    public func append(_ sample: SensorSample) throws {
        guard case .imu(let path, let imu) = sample,
              path == .spuGyroscope else { return }
        if let previous = lastGyroscopeTimestamp,
           imu.timestamp < previous {
            throw TapRegionStreamError.nonMonotonicTimestamp(
                previous: previous,
                current: imu.timestamp
            )
        }
        lastGyroscopeTimestamp = imu.timestamp
        gyroscopeSamples.append(imu)
        let cutoff = imu.timestamp - bufferDurationS
        if let firstRetained = gyroscopeSamples.firstIndex(where: {
            $0.timestamp >= cutoff
        }), firstRetained > 0 {
            gyroscopeSamples.removeFirst(firstRetained)
        }
    }

    public func classify(
        group: TapGroup,
        profile: TapRegionCalibrationProfile
    ) -> TapRegionClassification {
        guard group.members.count == TapRegionPattern.double.memberCount ||
                group.members.count == TapRegionPattern.triple.memberCount else {
            return TapRegionClassification(
                prediction: .unknown,
                reason: .unsupportedTapCount
            )
        }
        guard profile.isValid else {
            return TapRegionClassification(
                prediction: .unknown,
                reason: .invalidProfile
            )
        }
        do {
            let (features, median) = try features(for: group)
            let prediction = profile.predict(feature: median)
            return TapRegionClassification(
                prediction: prediction,
                reason: prediction == .unknown ? .ambiguous : .resolved,
                memberFeatures: features,
                aggregatedFeature: median,
                profileVersion: profile.version
            )
        } catch {
            return TapRegionClassification(
                prediction: .unknown,
                reason: .insufficientGyroscopeData,
                profileVersion: profile.version
            )
        }
    }

    public func features(
        for group: TapGroup
    ) throws -> (members: [TapRegionMemberFeature], median: Double) {
        guard group.members.count == TapRegionPattern.double.memberCount ||
                group.members.count == TapRegionPattern.triple.memberCount else {
            throw TapRegionFeatureExtractionError.missingPeakWindow
        }
        let features = try group.members.map {
            try extractor.extract(
                gyroscope: gyroscopeSamples,
                peakTimestamp: $0.time
            )
        }
        let sorted = features.map(\.gyroXPeakBalanceDegS).sorted()
        let middle = sorted.count / 2
        let median = sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2
            : sorted[middle]
        return (features, median)
    }

    public func reset() {
        gyroscopeSamples.removeAll(keepingCapacity: true)
        lastGyroscopeTimestamp = nil
    }
}
