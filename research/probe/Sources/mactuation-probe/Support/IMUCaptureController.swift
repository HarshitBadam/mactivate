import Darwin
import Foundation
import MactuationCapture
import MactuationCore
import MactuationHardware
import MactuationResearch

final class IMUCaptureController {
    let source: SPUIMUSource
    let label: String
    let markerEnabled: Bool
    let requestedDuration: TimeInterval
    let startedAt = Date()

    private(set) var startUptime = ProcessInfo.processInfo.systemUptime
    private var writer: CaptureWriter?
    private var _captureError: Error?
    private var markerRepetition = 0
    private var finalized = false
    private var discarded = false
    private let writerLock = NSLock()
    private let tapLock = NSLock()
    private let tapStream: TapStreamClassifier?
    private var tapCandidates: [TapEventFeatures] = []
    private var tapGroups: [TapGroup] = []
    private var latestAccelerometerTimestamp: SensorTimestamp = 0

    var captureError: Error? {
        writerLock.lock()
        defer { writerLock.unlock() }
        return _captureError
    }

    init(
        source: SPUIMUSource,
        label: String,
        markerEnabled: Bool,
        duration: TimeInterval,
        tapDetectionRateHz: Double? = nil
    ) {
        self.source = source
        self.label = label
        self.markerEnabled = markerEnabled
        requestedDuration = duration
        tapStream = tapDetectionRateHz.flatMap {
            try? TapStreamClassifier(sampleRateHz: $0)
        }
    }

    func start() throws {
        startUptime = ProcessInfo.processInfo.systemUptime
        do {
            let environment = collectCaptureEnvironment(
                requiredPrivileges: geteuid() == 0 ? ["root"] : []
            )
            let manifest = SessionManifest(
                label: label,
                startedAt: startedAt,
                toolVersion: toolVersion,
                environment: environment,
                sensors: source.paths.map {
                    SessionManifest.SensorRecord(
                        path: $0,
                        file: CaptureFormat.streamFileName(for: $0)
                    )
                }
            )
            writer = try CaptureWriter(
                directory: CaptureWriter.conventionalDirectory(
                    under: capturesRoot, label: label, startedAt: startedAt
                ),
                manifest: manifest
            )
            try source.start { [weak self] event in
                guard let self else { return }
                switch event {
                case .sample(let sample):
                    self.appendSample(sample)
                    self.processTapDetection(sample)
                case .failed(_, let reason):
                    self.setCaptureError(ProbeError.hardware(reason))
                case .warning(_, let message):
                    FileHandle.standardError.write(
                        Data("warning: \(message)\n".utf8)
                    )
                case .completed:
                    break
                }
            }
        } catch {
            source.stop()
            if let directory = writer?.directory {
                try? FileManager.default.removeItem(at: directory)
            }
            writer = nil
            throw error
        }
    }

    func addMarker() {
        guard markerEnabled else { return }
        writerLock.lock()
        defer { writerLock.unlock() }
        guard let writer else { return }
        markerRepetition += 1
        let now = max(0, ProcessInfo.processInfo.systemUptime - startUptime)
        writer.addLabel(LabelSpan(
            start: now,
            end: now + 0.5,
            label: label,
            repetition: markerRepetition
        ))
        print(String(format: "Marker %d at %.6f s", markerRepetition, now))
    }

    func addRegionMarker(
        side: TapRegionProbeSide,
        intensity: TapRegionProbeIntensity,
        repetition: Int,
        candidate: TapEventFeatures,
        preRoll: Double = 0.15,
        postRoll: Double = 0.50
    ) {
        guard markerEnabled else { return }
        writerLock.lock()
        defer { writerLock.unlock() }
        guard let writer else { return }
        writer.addLabel(LabelSpan(
            start: max(0, candidate.time - preRoll),
            end: candidate.time + postRoll,
            label: "palm-\(side.rawValue)",
            repetition: repetition,
            intensity: intensity.rawValue,
            notes: "auto-detected general tap; peak=\(candidate.time)"
        ))
    }

    func addRegionMultiTapLabels(
        side: TapRegionProbeSide,
        pattern: TapRegionMultiTapPattern,
        repetition: Int,
        group: TapGroup,
        preRoll: Double = 0.15,
        postRoll: Double = 0.50
    ) {
        guard markerEnabled else { return }
        writerLock.lock()
        defer { writerLock.unlock() }
        guard let writer else { return }
        for (offset, member) in group.members.enumerated() {
            writer.addLabel(LabelSpan(
                start: max(0, member.time - preRoll),
                end: member.time + postRoll,
                label: "palm-\(side.rawValue)",
                repetition: repetition,
                intensity: pattern.analysisIntensity.rawValue,
                notes: "auto-detected multi-tap; pattern=\(pattern.rawValue); " +
                    "member=\(offset + 1)/\(group.members.count); peak=\(member.time)"
            ))
        }
    }

    func addRestLabel(start: Double, end: Double) {
        guard markerEnabled else { return }
        writerLock.lock()
        defer { writerLock.unlock() }
        guard let writer else { return }
        writer.addLabel(LabelSpan(
            start: start,
            end: end,
            label: "rest",
            repetition: 1,
            notes: "hands off; Mac stationary on hard table"
        ))
    }

    var captureDirectory: URL? {
        writerLock.lock()
        defer { writerLock.unlock() }
        return writer?.directory
    }

    var latestTapSensorTimestamp: SensorTimestamp {
        tapLock.lock()
        defer { tapLock.unlock() }
        return latestAccelerometerTimestamp
    }

    func consumeTapCandidate(
        after timestamp: SensorTimestamp
    ) -> TapEventFeatures? {
        tapLock.lock()
        defer { tapLock.unlock() }
        tapCandidates.removeAll { $0.time <= timestamp }
        guard !tapCandidates.isEmpty else { return nil }
        return tapCandidates.removeFirst()
    }

    func consumeTapGroup(after timestamp: SensorTimestamp) -> TapGroup? {
        tapLock.lock()
        defer { tapLock.unlock() }
        tapGroups.removeAll {
            guard let first = $0.members.first else { return true }
            return first.time <= timestamp
        }
        guard !tapGroups.isEmpty else { return nil }
        return tapGroups.removeFirst()
    }

    func finish() throws {
        guard !finalized, !discarded else { return }
        finalized = true
        let elapsed = max(0, ProcessInfo.processInfo.systemUptime - startUptime)

        source.stop()
        writerLock.lock()
        defer { writerLock.unlock() }
        guard let writer else { return }
        if !markerEnabled {
            writer.addLabel(LabelSpan(
                start: 0,
                end: min(requestedDuration, elapsed),
                label: label,
                repetition: 1
            ))
        }

        let wakeProperties = source.wakePropertiesSet.joined(separator: ",")
        for path in source.paths {
            var parameters = [
                "wake_required": String(source.wakeRequired),
                "wake_properties_set": wakeProperties,
                "restoration": "saved ReportInterval; absent state properties restored to 0",
                "decode_offsets": "6,10,14",
                "decode_scale": "65536"
            ]
            if let interval = source.reportIntervalUsed {
                parameters["ReportInterval"] = String(interval)
            }
            if let firstLength = source.firstReportLength(for: path) {
                parameters["first_report_length"] = String(firstLength)
            }
            writer.recordSensorMetadata(
                path: path,
                effectiveRateHz: source.effectiveRate(for: path, elapsed: elapsed),
                acquisitionParameters: parameters,
                anomalies: source.anomalies(for: path) +
                    (source.malformedReport.map { [$0] } ?? [])
            )
        }
        try writer.finalize()
        print("Capture directory: \(writer.directory.path)")
    }

    func discard() {
        guard !finalized, !discarded else { return }
        discarded = true
        source.stop()
        writerLock.lock()
        defer { writerLock.unlock() }
        if let directory = writer?.directory {
            try? FileManager.default.removeItem(at: directory)
        }
        writer = nil
    }

    private func setCaptureError(_ error: Error) {
        writerLock.lock()
        if _captureError == nil { _captureError = error }
        writerLock.unlock()
    }

    private func appendSample(_ sample: SensorSample) {
        writerLock.lock()
        defer { writerLock.unlock() }
        guard _captureError == nil else { return }
        do {
            try writer?.append(sample)
        } catch {
            _captureError = error
        }
    }

    private func processTapDetection(_ sample: SensorSample) {
        guard case .imu(let path, let imu) = sample,
              path == .spuAccelerometer,
              let tapStream else { return }
        tapLock.lock()
        defer { tapLock.unlock() }
        latestAccelerometerTimestamp = imu.timestamp
        do {
            let update = try tapStream.appendWithFeedback(imu)
            tapCandidates.append(contentsOf: update.candidates)
            tapGroups.append(contentsOf: update.resolvedGroups)
        } catch {
            setCaptureError(error)
        }
    }
}
