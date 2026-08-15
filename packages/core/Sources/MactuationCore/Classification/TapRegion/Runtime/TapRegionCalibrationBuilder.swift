import Foundation

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
        return memberFeatures.sorted().medianOfSorted
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

/// Uses the same held-out qualification metric as offline fitting so personal
/// profiles and research fits meet one acceptance bar.
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
