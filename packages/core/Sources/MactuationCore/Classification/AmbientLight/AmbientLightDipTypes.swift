import Foundation

public struct AmbientLightDipCalibration: Codable, Equatable, Sendable {
    public var version: String
    public var warmupSampleCount: Int
    public var minimumBaselineLux: Double
    public var floorLux: Double
    public var floorConfirmationS: Double
    public var minimumAbsoluteDropLux: Double
    public var minimumRelativeDrop: Double
    public var recoveryFraction: Double
    public var maximumDipS: Double
    public var baselineSmoothingFactor: Double
    public var cooldownS: Double

    public init(version: String, warmupSampleCount: Int,
                minimumBaselineLux: Double, floorLux: Double,
                floorConfirmationS: Double, minimumAbsoluteDropLux: Double,
                minimumRelativeDrop: Double, recoveryFraction: Double,
                maximumDipS: Double, baselineSmoothingFactor: Double,
                cooldownS: Double) {
        self.version = version
        self.warmupSampleCount = warmupSampleCount
        self.minimumBaselineLux = minimumBaselineLux
        self.floorLux = floorLux
        self.floorConfirmationS = floorConfirmationS
        self.minimumAbsoluteDropLux = minimumAbsoluteDropLux
        self.minimumRelativeDrop = minimumRelativeDrop
        self.recoveryFraction = recoveryFraction
        self.maximumDipS = maximumDipS
        self.baselineSmoothingFactor = baselineSmoothingFactor
        self.cooldownS = cooldownS
    }

    /// Initial heuristic for the measured Mac14,2 path. Favorable-light dips
    /// were observed around 260 lux; the actual lower operating boundary is
    /// only known to lie between roughly 1 and 30 lux.
    public static let mac14_2Experimental = AmbientLightDipCalibration(
        version: "mac14_2-als-dip-experimental-1",
        warmupSampleCount: 20,
        minimumBaselineLux: 30,
        floorLux: 1.5,
        floorConfirmationS: 1,
        minimumAbsoluteDropLux: 5,
        minimumRelativeDrop: 0.20,
        recoveryFraction: 0.90,
        maximumDipS: 3,
        baselineSmoothingFactor: 0.02,
        cooldownS: 2
    )
}

public enum AmbientLightReadiness: Equatable, Sendable {
    case warmingUp
    case available
    case tooDim
}

public struct PanelOpenHint: Equatable, Sendable {
    public let timestamp: SensorTimestamp
    public let baselineLux: Double
    public let observedLux: Double
    public let relativeDrop: Double

    public init(timestamp: SensorTimestamp, baselineLux: Double,
                observedLux: Double, relativeDrop: Double) {
        self.timestamp = timestamp
        self.baselineLux = baselineLux
        self.observedLux = observedLux
        self.relativeDrop = relativeDrop
    }
}

public enum AmbientLightDipEvent: Equatable, Sendable {
    case readinessChanged(AmbientLightReadiness)
    case panelOpenHint(PanelOpenHint)
}

public enum AmbientLightDipError: Error, Equatable, CustomStringConvertible {
    case invalidConfiguration(String)
    case invalidLux(Double)
    case nonMonotonicTimestamp(previous: SensorTimestamp, current: SensorTimestamp)

    public var description: String {
        switch self {
        case .invalidConfiguration(let reason):
            return reason
        case .invalidLux(let lux):
            return "ambient-light reading must be finite and non-negative, got \(lux)"
        case .nonMonotonicTimestamp(let previous, let current):
            return "ALS timestamp moved backwards from \(previous) to \(current)"
        }
    }
}
