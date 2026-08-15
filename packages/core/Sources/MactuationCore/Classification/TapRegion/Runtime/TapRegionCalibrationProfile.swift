import Foundation

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
        var digest = DeterministicDigest()
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
