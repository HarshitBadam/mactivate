import Foundation

public enum TapStreamError: Error, Equatable, CustomStringConvertible {
    case invalidConfiguration(String)
    case nonMonotonicTimestamp(previous: SensorTimestamp, current: SensorTimestamp)

    public var description: String {
        switch self {
        case .invalidConfiguration(let reason):
            return reason
        case .nonMonotonicTimestamp(let previous, let current):
            return "IMU timestamp moved backwards from \(previous) to \(current)"
        }
    }
}

public struct TapStreamConfiguration: Equatable, Sendable {
    public var bufferDurationS: Double
    public var classificationIntervalS: Double
    public var rateWarmupS: Double

    public init(bufferDurationS: Double = 4,
                classificationIntervalS: Double = 0.1,
                rateWarmupS: Double = 1) {
        self.bufferDurationS = bufferDurationS
        self.classificationIntervalS = classificationIntervalS
        self.rateWarmupS = rateWarmupS
    }
}

/// Bounded live adapter for the deterministic batch tap rule.
///
/// `append` returns each newly resolved group once, including rejected groups
/// for diagnostics. Product consumers dispatch only groups whose verdict is
/// accepted. Resolution waits for centered-detrend lookahead, peak-tail
/// completion, and the full grouping gap.
public final class TapStreamClassifier {
    public let classifier: TapClassifier
    public let configuration: TapStreamConfiguration

    public private(set) var sampleRateHz: Double?
    public private(set) var lastResolvedThrough: SensorTimestamp?
    public var bufferedSampleCount: Int { samples.count }

    private let configuredSampleRateHz: Double?
    private var samples: [IMUSample] = []
    private var lastSampleTimestamp: SensorTimestamp?
    private var lastClassificationTimestamp: SensorTimestamp?
    private var emittedIDs: [String: SensorTimestamp] = [:]
    private var emittedMemberTimes: [String: SensorTimestamp] = [:]
    private var hasTrimmed = false
    private var committedMemberThrough: SensorTimestamp?

    public init(calibration: TapCalibration = .mac14_2Discovery,
                sampleRateHz: Double? = nil,
                configuration: TapStreamConfiguration = TapStreamConfiguration()) throws {
        guard configuration.bufferDurationS.isFinite,
              configuration.classificationIntervalS.isFinite,
              configuration.rateWarmupS.isFinite,
              configuration.bufferDurationS >
                calibration.detrendWindowS / 2 +
                calibration.refractoryS +
                calibration.groupGapS,
              configuration.classificationIntervalS > 0,
              configuration.rateWarmupS > 0 else {
            throw TapStreamError.invalidConfiguration(
                "tap stream durations must be positive and the buffer must exceed " +
                    "detrend lookahead + refractory + group gap"
            )
        }
        if let sampleRateHz {
            guard sampleRateHz.isFinite, sampleRateHz > 0 else {
                throw TapStreamError.invalidConfiguration(
                    "sample rate must be finite and greater than zero"
                )
            }
        }
        classifier = TapClassifier(calibration: calibration)
        self.configuration = configuration
        configuredSampleRateHz = sampleRateHz
        self.sampleRateHz = sampleRateHz
    }

    public func append(_ sample: SensorSample,
                       path: SensorPath = .spuAccelerometer) throws -> [TapGroup] {
        guard case .imu(let samplePath, let imu) = sample, samplePath == path else {
            return []
        }
        return try append(imu)
    }

    public func append(_ sample: IMUSample) throws -> [TapGroup] {
        if let previous = lastSampleTimestamp, sample.timestamp < previous {
            throw TapStreamError.nonMonotonicTimestamp(
                previous: previous,
                current: sample.timestamp
            )
        }
        lastSampleTimestamp = sample.timestamp
        samples.append(sample)
        freezeSampleRateIfReady()
        trimBuffer()

        guard sampleRateHz != nil else { return [] }
        if let lastClassificationTimestamp,
           sample.timestamp - lastClassificationTimestamp <
            configuration.classificationIntervalS {
            return []
        }
        lastClassificationTimestamp = sample.timestamp
        return classifyBuffered(endOfInput: false)
    }

    /// Resolves the truncated right edge for finite replay and diagnostics.
    /// Runtime shutdown should call `reset()` instead, so quitting cannot
    /// dispatch a gesture whose grouping window had not elapsed.
    public func finishForReplay() -> [TapGroup] {
        guard samples.count >= 2 else { return [] }
        if sampleRateHz == nil {
            let duration = samples[samples.count - 1].timestamp - samples[0].timestamp
            if duration > 0 {
                sampleRateHz = Double(samples.count - 1) / duration
            }
        }
        guard sampleRateHz != nil else { return [] }
        return classifyBuffered(endOfInput: true)
    }

    public func reset() {
        samples.removeAll(keepingCapacity: true)
        lastSampleTimestamp = nil
        lastClassificationTimestamp = nil
        emittedIDs.removeAll(keepingCapacity: true)
        emittedMemberTimes.removeAll(keepingCapacity: true)
        hasTrimmed = false
        committedMemberThrough = nil
        lastResolvedThrough = nil
        sampleRateHz = configuredSampleRateHz
    }

    private func freezeSampleRateIfReady() {
        guard sampleRateHz == nil, samples.count >= 2 else { return }
        let duration = samples[samples.count - 1].timestamp - samples[0].timestamp
        guard duration >= configuration.rateWarmupS, duration > 0 else { return }
        sampleRateHz = Double(samples.count - 1) / duration
    }

    private func trimBuffer() {
        guard let last = samples.last?.timestamp else { return }
        let cutoff = last - configuration.bufferDurationS
        guard let firstRetained = samples.firstIndex(where: { $0.timestamp >= cutoff }),
              firstRetained > 0 else { return }
        samples.removeFirst(firstRetained)
        hasTrimmed = true
        guard let bufferStart = samples.first?.timestamp else {
            emittedIDs.removeAll()
            return
        }
        emittedIDs = emittedIDs.filter { $0.value >= bufferStart }
        emittedMemberTimes = emittedMemberTimes.filter { $0.value >= bufferStart }
    }

    private func classifyBuffered(endOfInput: Bool) -> [TapGroup] {
        guard let sampleRateHz, samples.count >= 2 else { return [] }
        let ignoredPrefix = hasTrimmed
            ? max(1, Int(classifier.calibration.detrendWindowS * sampleRateHz / 2))
            : 0
        let analysis = classifier.analyze(
            imuSamples: samples,
            sampleRateHz: sampleRateHz,
            endOfInput: endOfInput,
            detectionStartIndex: ignoredPrefix
        )
        lastResolvedThrough = analysis.resolvedThrough
        let previousCommitWatermark = committedMemberThrough

        var newlyResolved: [TapGroup] = []
        for group in analysis.groups {
            guard let lastMemberTime = group.members.last?.time,
                  previousCommitWatermark == nil ||
                    lastMemberTime > previousCommitWatermark! else {
                continue
            }
            let identifier = group.eventID(
                calibrationVersion: classifier.calibration.version
            )
            let memberIdentifiers = group.members.map {
                CaptureFormat.encode($0.time)
            }
            guard emittedIDs[identifier] == nil,
                  memberIdentifiers.allSatisfy({ emittedMemberTimes[$0] == nil }),
                  let timestamp = group.members.first?.time else { continue }
            emittedIDs[identifier] = timestamp
            for (memberIdentifier, member) in zip(memberIdentifiers, group.members) {
                emittedMemberTimes[memberIdentifier] = member.time
            }
            newlyResolved.append(group)
        }
        if let resolvedThrough = analysis.resolvedThrough {
            let newWatermark = endOfInput
                ? resolvedThrough
                : resolvedThrough - classifier.calibration.groupGapS
            committedMemberThrough = max(
                committedMemberThrough ?? -Double.greatestFiniteMagnitude,
                newWatermark
            )
        }
        return newlyResolved
    }
}
