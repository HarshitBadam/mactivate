import Foundation

/// Reproduces `tools/analysis/analyze_imu.py`'s pipeline operation-for-operation —
/// centered moving-average detrend, threshold + refractory event detection,
/// ±25 ms signed impulses, gap grouping — followed by the tiered accept rule
/// validated in docs/probe-results/2026-07-24-mac14-2-discovery.md.
///
/// Later group members are never gated — ring-down from a prior tap flips
/// their impulse sign ~45% of the time (measured), so only the first member
/// carries signal.
///
/// Batch by design: the validated detrend is centered (needs lookahead), and
/// classification runs against recorded or buffered streams. Determinism
/// contract: identical samples + identical calibration ⇒ identical `TapGroup`
/// array and byte-identical `digest(of:)`.
public struct TapClassifier: Sendable {
    public let calibration: TapCalibration

    public init(calibration: TapCalibration) {
        self.calibration = calibration
    }

    public func classify(samples: [SensorSample], path: SensorPath = .spuAccelerometer) -> [TapGroup] {
        let imu = samples.compactMap { sample -> IMUSample? in
            guard case .imu(let samplePath, let imuSample) = sample, samplePath == path else { return nil }
            return imuSample
        }
        return classify(imuSamples: imu)
    }

    public func classify(imuSamples rows: [IMUSample]) -> [TapGroup] {
        let n = rows.count
        guard n >= 2 else { return [] }
        let times = rows.map(\.timestamp)
        let duration = times[n - 1] - times[0]
        guard duration > 0 else { return [] }
        let rate = Double(n - 1) / duration
        return classify(imuSamples: rows, sampleRateHz: rate)
    }

    /// Classifies with a caller-supplied effective rate. Live replay uses this
    /// overload so overlapping windows cannot change integer window sizes due
    /// to tiny timestamp-jitter differences.
    public func classify(imuSamples rows: [IMUSample],
                         sampleRateHz rate: Double) -> [TapGroup] {
        analyze(
            imuSamples: rows,
            sampleRateHz: rate,
            endOfInput: true,
            detectionStartIndex: 0
        ).groups
    }

    func analyze(imuSamples rows: [IMUSample], sampleRateHz rate: Double,
                 endOfInput: Bool, detectionStartIndex: Int) -> TapClassifierAnalysis {
        let n = rows.count
        guard n >= 2, rate.isFinite, rate > 0 else {
            return TapClassifierAnalysis(
                groups: [],
                candidates: [],
                resolvedThrough: nil
            )
        }
        let times = rows.map(\.timestamp)
        // Centered moving-average high-pass, mirroring analyze_imu.py:
        // per-axis prefix sums, window [i-half, i+half], residual magnitude
        // accumulated in x, y, z order so float rounding matches.
        let half = max(1, Int(calibration.detrendWindowS * rate / 2))
        var residualSquared = [Double](repeating: 0, count: n)
        var signedResiduals: [[Double]] = []
        for values in [rows.map(\.x), rows.map(\.y), rows.map(\.z)] {
            var prefix = [Double](repeating: 0, count: n + 1)
            for i in 0..<n {
                prefix[i + 1] = prefix[i] + values[i]
            }
            var signed = [Double](repeating: 0, count: n)
            for i in 0..<n {
                let lo = max(0, i - half)
                let hi = min(n, i + half + 1)
                let mean = (prefix[hi] - prefix[lo]) / Double(hi - lo)
                signed[i] = values[i] - mean
                residualSquared[i] += signed[i] * signed[i]
            }
            signedResiduals.append(signed)
        }
        let magnitude = residualSquared.map { $0.squareRoot() }

        let stableEnd = endOfInput ? n : max(0, n - half)
        guard stableEnd > 0 else {
            return TapClassifierAnalysis(
                groups: [],
                candidates: [],
                resolvedThrough: nil
            )
        }
        let detection = detectEvents(
            times: times,
            magnitude: magnitude,
            rate: rate,
            signedResiduals: signedResiduals,
            startIndex: min(max(0, detectionStartIndex), stableEnd),
            endIndex: stableEnd,
            requireCompleteSupport: !endOfInput
        )
        let groups = groupAndJudge(events: detection.events)
        guard !endOfInput else {
            return TapClassifierAnalysis(
                groups: groups,
                candidates: detection.events,
                resolvedThrough: times.last
            )
        }
        guard let resolvedThrough = detection.resolvedThrough else {
            return TapClassifierAnalysis(
                groups: [],
                candidates: detection.events,
                resolvedThrough: nil
            )
        }
        return TapClassifierAnalysis(
            groups: groups.filter {
                guard let last = $0.members.last else { return false }
                return last.time + calibration.groupGapS <= resolvedThrough
            },
            candidates: detection.events,
            resolvedThrough: resolvedThrough
        )
    }

    private struct EventDetection {
        var events: [TapEventFeatures]
        var resolvedThrough: SensorTimestamp?
    }

    private func detectEvents(times: [SensorTimestamp], magnitude: [Double], rate: Double,
                              signedResiduals: [[Double]], startIndex: Int,
                              endIndex: Int,
                              requireCompleteSupport: Bool) -> EventDetection {
        let threshold = calibration.eventThresholdG
        let refractory = max(1, Int(calibration.refractoryS * rate))
        let impulseHalf = max(1, Int(calibration.impulseHalfWindowS * rate))

        var events: [TapEventFeatures] = []
        var resolvedEndIndex = endIndex - 1
        var i = startIndex
        while i < endIndex {
            let isPersonalCalibration = calibration.version.hasPrefix("personal-")
            let isLaterGroupMember = isPersonalCalibration &&
                events.last.map {
                    times[i] - $0.time <= calibration.groupGapS
                } == true
            let activeThreshold = isLaterGroupMember ? threshold * 0.65 : threshold
            guard magnitude[i] >= activeThreshold else {
                i += 1
                continue
            }
            if requireCompleteSupport && i + refractory > endIndex {
                resolvedEndIndex = i - 1
                break
            }
            let end = min(endIndex, i + refractory)
            // First index of the maximum, matching Python max()'s tie behavior.
            var peakIdx = i
            for j in i..<end where magnitude[j] > magnitude[peakIdx] {
                peakIdx = j
            }
            if requireCompleteSupport && peakIdx + impulseHalf >= endIndex {
                resolvedEndIndex = i - 1
                break
            }
            var tail = peakIdx
            while tail < endIndex - 1 &&
                magnitude[tail + 1] > activeThreshold / 2 {
                tail += 1
            }
            if requireCompleteSupport && tail == endIndex - 1 &&
                magnitude[tail] > activeThreshold / 2 {
                resolvedEndIndex = i - 1
                break
            }
            let decayMs = (times[tail] - times[peakIdx]) * 1000

            let lo = max(0, peakIdx - impulseHalf)
            let hi = min(endIndex, peakIdx + impulseHalf + 1)
            var impulses = [Double](repeating: 0, count: 3)
            for axis in 0..<3 {
                var sum = 0.0
                for j in lo..<hi {
                    sum += signedResiduals[axis][j]
                }
                impulses[axis] = sum / rate
            }
            let candidate = TapEventFeatures(
                time: times[peakIdx],
                peakG: magnitude[peakIdx],
                decayMs: decayMs,
                zImpulseMgS: impulses[2] * 1000,
                lateralImpulseMgS:
                    (abs(impulses[0]) + abs(impulses[1])) * 1000
            )
            let isPeakScaledAftershock = isPersonalCalibration &&
                events.last.map {
                    candidate.time - $0.time <= 0.22 &&
                        candidate.peakG < $0.peakG * 0.45
                } == true
            if !isPeakScaledAftershock {
                events.append(candidate)
            }
            i = max(peakIdx + refractory, tail + 1)
        }
        let resolvedThrough = resolvedEndIndex >= startIndex
            ? times[resolvedEndIndex]
            : nil
        return EventDetection(events: events, resolvedThrough: resolvedThrough)
    }

    private func groupAndJudge(events: [TapEventFeatures]) -> [TapGroup] {
        var groups: [[TapEventFeatures]] = []
        for event in events {
            if let last = groups.last?.last, event.time - last.time <= calibration.groupGapS {
                groups[groups.count - 1].append(event)
            } else {
                groups.append([event])
            }
        }
        return groups.map { members in
            let result = verdict(for: members)
            return TapGroup(
                members: members,
                verdict: result.verdict,
                rejectionReason: result.reason
            )
        }
    }

    private func verdict(
        for members: [TapEventFeatures]
    ) -> (verdict: TapVerdict, reason: TapRejectionReason?) {
        guard let first = members.first else {
            return (.rejected, .noMembers)
        }
        guard members.count <= calibration.maxGroupMembers else {
            return (.rejected, .tooManyMembers)
        }
        // Amplitude selects the tier. A firm candidate must pass the scaled
        // firm veto; it cannot fall back to the looser comfort gate merely
        // because its Z impulse is positive.
        let matchingFirmTiers = calibration.firmTiers.keys.sorted().compactMap {
            side -> (PalmSide, TapCalibration.FirmTier)? in
            guard let tier = calibration.firmTiers[side],
                  first.peakG >= tier.amplitudeCutG else {
                return nil
            }
            return (side, tier)
        }
        if !matchingFirmTiers.isEmpty {
            for (side, tier) in matchingFirmTiers
            where first.lateralImpulseMgS / first.peakG <=
                tier.lateralToPeakMaxMgSPerG &&
                first.decayMs <= tier.decayMaxMs {
                return (.acceptedFirm(side), nil)
            }
            let passesLateral = matchingFirmTiers.contains { _, tier in
                first.lateralImpulseMgS / first.peakG <=
                    tier.lateralToPeakMaxMgSPerG
            }
            return (
                .rejected,
                passesLateral ? .firmDecay : .firmLateralImpulse
            )
        }
        guard first.zImpulseMgS > 0 else {
            return (.rejected, .comfortZImpulse)
        }
        guard first.lateralImpulseMgS < calibration.comfortLateralVetoMgS else {
            return (.rejected, .comfortLateralImpulse)
        }
        return (.acceptedComfort, nil)
    }
}
