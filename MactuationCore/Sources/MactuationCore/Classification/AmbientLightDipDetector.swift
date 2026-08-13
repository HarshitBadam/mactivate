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

/// Deterministic detector for a short ambient-light dip.
///
/// This does not identify a hand. The resulting hint is deliberately
/// non-actionable: ordinary walking shadows can produce stronger signals.
public final class AmbientLightDipDetector {
    public let calibration: AmbientLightDipCalibration
    public private(set) var readiness: AmbientLightReadiness = .warmingUp
    public private(set) var baselineLux: Double?

    private enum Phase {
        case monitoring
        case dip(startedAt: SensorTimestamp)
        case cooldown(until: SensorTimestamp)
    }

    private var phase: Phase = .monitoring
    private var warmupValues: [Double] = []
    private var floorStartedAt: SensorTimestamp?
    private var lastTimestamp: SensorTimestamp?

    public init(calibration: AmbientLightDipCalibration = .mac14_2Experimental) throws {
        guard !calibration.version.isEmpty,
              calibration.warmupSampleCount > 0,
              calibration.minimumBaselineLux.isFinite,
              calibration.minimumBaselineLux > 0,
              calibration.floorLux.isFinite,
              calibration.floorLux >= 0,
              calibration.floorLux < calibration.minimumBaselineLux,
              calibration.floorConfirmationS.isFinite,
              calibration.floorConfirmationS > 0,
              calibration.minimumAbsoluteDropLux.isFinite,
              calibration.minimumAbsoluteDropLux > 0,
              calibration.minimumRelativeDrop > 0,
              calibration.minimumRelativeDrop < 1,
              calibration.recoveryFraction > 0,
              calibration.recoveryFraction <= 1,
              calibration.maximumDipS.isFinite,
              calibration.maximumDipS > 0,
              calibration.baselineSmoothingFactor > 0,
              calibration.baselineSmoothingFactor <= 1,
              calibration.cooldownS.isFinite,
              calibration.cooldownS >= 0 else {
            throw AmbientLightDipError.invalidConfiguration(
                "ambient-light calibration contains invalid thresholds"
            )
        }
        self.calibration = calibration
        warmupValues.reserveCapacity(calibration.warmupSampleCount)
    }

    public func process(_ sample: SensorSample,
                        path: SensorPath = .spuAmbientLight) throws
        -> [AmbientLightDipEvent] {
        guard case .als(let samplePath, let als) = sample, samplePath == path else {
            return []
        }
        return try process(als)
    }

    public func process(_ sample: ALSSample) throws -> [AmbientLightDipEvent] {
        guard sample.lux.isFinite, sample.lux >= 0 else {
            throw AmbientLightDipError.invalidLux(sample.lux)
        }
        if let lastTimestamp, sample.timestamp < lastTimestamp {
            throw AmbientLightDipError.nonMonotonicTimestamp(
                previous: lastTimestamp,
                current: sample.timestamp
            )
        }
        lastTimestamp = sample.timestamp

        switch readiness {
        case .warmingUp:
            return collectWarmup(sample.lux)
        case .tooDim:
            return recoverFromDimIfPossible(sample.lux)
        case .available:
            return processAvailable(sample)
        }
    }

    public func reset() {
        readiness = .warmingUp
        baselineLux = nil
        phase = .monitoring
        warmupValues.removeAll(keepingCapacity: true)
        floorStartedAt = nil
        lastTimestamp = nil
    }

    private func collectWarmup(_ lux: Double) -> [AmbientLightDipEvent] {
        warmupValues.append(lux)
        guard warmupValues.count >= calibration.warmupSampleCount else { return [] }
        let baseline = warmupValues.reduce(0, +) / Double(warmupValues.count)
        warmupValues.removeAll(keepingCapacity: true)
        baselineLux = baseline
        if baseline < calibration.minimumBaselineLux {
            readiness = .tooDim
            return [.readinessChanged(.tooDim)]
        }
        readiness = .available
        return [.readinessChanged(.available)]
    }

    private func recoverFromDimIfPossible(_ lux: Double) -> [AmbientLightDipEvent] {
        guard lux >= calibration.minimumBaselineLux else {
            warmupValues.removeAll(keepingCapacity: true)
            return []
        }
        warmupValues.append(lux)
        guard warmupValues.count >= calibration.warmupSampleCount else { return [] }
        baselineLux = warmupValues.reduce(0, +) / Double(warmupValues.count)
        warmupValues.removeAll(keepingCapacity: true)
        readiness = .available
        phase = .monitoring
        floorStartedAt = nil
        return [.readinessChanged(.available)]
    }

    private func processAvailable(_ sample: ALSSample) -> [AmbientLightDipEvent] {
        guard let baseline = baselineLux else {
            readiness = .warmingUp
            return [.readinessChanged(.warmingUp)]
        }

        switch phase {
        case .dip(let startedAt):
            if sample.lux <= calibration.floorLux {
                if floorStartedAt == nil { floorStartedAt = sample.timestamp }
                if let floorStartedAt,
                   sample.timestamp - floorStartedAt >=
                    calibration.floorConfirmationS {
                    readiness = .tooDim
                    baselineLux = sample.lux
                    warmupValues.removeAll(keepingCapacity: true)
                    phase = .monitoring
                    return [.readinessChanged(.tooDim)]
                }
            } else {
                floorStartedAt = nil
            }
            if sample.lux >= baseline * calibration.recoveryFraction {
                phase = .cooldown(until: sample.timestamp + calibration.cooldownS)
                floorStartedAt = nil
            } else if sample.timestamp - startedAt >= calibration.maximumDipS {
                phase = .monitoring
                floorStartedAt = nil
                if sample.lux < calibration.minimumBaselineLux {
                    readiness = .tooDim
                    baselineLux = sample.lux
                    warmupValues.removeAll(keepingCapacity: true)
                    return [.readinessChanged(.tooDim)]
                }
                readiness = .warmingUp
                baselineLux = nil
                warmupValues = [sample.lux]
                return [.readinessChanged(.warmingUp)]
            }
            return []
        case .cooldown(let until):
            if sample.timestamp < until {
                updateBaseline(with: sample.lux)
                return []
            }
            phase = .monitoring
        case .monitoring:
            break
        }

        if sample.lux <= calibration.floorLux {
            if floorStartedAt == nil { floorStartedAt = sample.timestamp }
            if let floorStartedAt,
               sample.timestamp - floorStartedAt >= calibration.floorConfirmationS {
                readiness = .tooDim
                baselineLux = sample.lux
                warmupValues.removeAll(keepingCapacity: true)
                phase = .monitoring
                return [.readinessChanged(.tooDim)]
            }
        } else {
            floorStartedAt = nil
        }

        let absoluteDrop = baseline - sample.lux
        let relativeDrop = baseline > 0 ? absoluteDrop / baseline : 0
        if absoluteDrop >= calibration.minimumAbsoluteDropLux,
           relativeDrop >= calibration.minimumRelativeDrop {
            phase = .dip(startedAt: sample.timestamp)
            return [.panelOpenHint(PanelOpenHint(
                timestamp: sample.timestamp,
                baselineLux: baseline,
                observedLux: sample.lux,
                relativeDrop: relativeDrop
            ))]
        }

        updateBaseline(with: sample.lux)
        if let baselineLux, baselineLux < calibration.minimumBaselineLux {
            readiness = .tooDim
            warmupValues.removeAll(keepingCapacity: true)
            phase = .monitoring
            return [.readinessChanged(.tooDim)]
        }
        return []
    }

    private func updateBaseline(with lux: Double) {
        guard let baselineLux else {
            self.baselineLux = lux
            return
        }
        let alpha = calibration.baselineSmoothingFactor
        self.baselineLux = baselineLux + alpha * (lux - baselineLux)
    }
}
