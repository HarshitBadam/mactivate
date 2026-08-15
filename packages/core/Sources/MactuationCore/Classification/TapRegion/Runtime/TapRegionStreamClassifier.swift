import Foundation

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
        let median = features.map(\.gyroXPeakBalanceDegS).sorted().medianOfSorted
        return (features, median)
    }

    public func reset() {
        gyroscopeSamples.removeAll(keepingCapacity: true)
        lastGyroscopeTimestamp = nil
    }
}
