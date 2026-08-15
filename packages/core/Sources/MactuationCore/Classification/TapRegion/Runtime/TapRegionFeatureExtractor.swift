import Foundation

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
