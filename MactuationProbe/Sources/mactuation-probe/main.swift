import Darwin
import Foundation
import MactuationCore
import MactuationHardware

enum ProbeError: Error, CustomStringConvertible {
    case usage(String)
    case hardware(String)
    case capture(String)

    var description: String {
        switch self {
        case .usage(let message), .hardware(let message), .capture(let message):
            return message
        }
    }
}

private struct Arguments {
    let values: [String]

    func has(_ flag: String) -> Bool {
        values.contains(flag)
    }

    func value(after flag: String) throws -> String? {
        guard let index = values.firstIndex(of: flag) else { return nil }
        guard values.indices.contains(index + 1), !values[index + 1].hasPrefix("--") else {
            throw ProbeError.usage("\(flag) requires a value")
        }
        return values[index + 1]
    }

    func double(after flag: String, default defaultValue: Double) throws -> Double {
        guard let raw = try value(after: flag) else { return defaultValue }
        guard let value = Double(raw), value.isFinite, value > 0 else {
            throw ProbeError.usage("\(flag) must be a positive number")
        }
        return value
    }

    func integer(after flag: String, default defaultValue: Int) throws -> Int {
        guard let raw = try value(after: flag) else { return defaultValue }
        guard let value = Int(raw), value > 0 else {
            throw ProbeError.usage("\(flag) must be a positive integer")
        }
        return value
    }
}

private final class ALSRunState {
    var samples: [ALSSample] = []
    var changeTimes: [Double] = []
    var previousLux: Double?
    private let lock = NSLock()
    private var _writeError: Error?
    private var _sourceError: String?

    var writeError: Error? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _writeError
        }
        set {
            lock.lock()
            _writeError = newValue
            lock.unlock()
        }
    }

    var sourceError: String? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _sourceError
        }
        set {
            lock.lock()
            _sourceError = newValue
            lock.unlock()
        }
    }
}

private final class TapWatchState: @unchecked Sendable {
    let stream: TapStreamClassifier

    private let lock = NSLock()
    private var _sourceError: String?
    private var _acceptedCount = 0
    private var _rejectedCount = 0

    init(stream: TapStreamClassifier) {
        self.stream = stream
    }

    var sourceError: String? {
        lock.lock()
        defer { lock.unlock() }
        return _sourceError
    }

    var counts: (accepted: Int, rejected: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (_acceptedCount, _rejectedCount)
    }

    func process(_ event: SensorSourceEvent) {
        switch event {
        case .sample(let sample):
            guard case .imu(.spuAccelerometer, let imu) = sample else { return }
            do {
                for group in try stream.append(imu) {
                    guard group.verdict.isAccepted else {
                        lock.lock()
                        _rejectedCount += 1
                        lock.unlock()
                        continue
                    }
                    lock.lock()
                    _acceptedCount += 1
                    lock.unlock()
                    let verdict: String
                    switch group.verdict {
                    case .acceptedComfort:
                        verdict = "comfort"
                    case .acceptedFirm(let side):
                        verdict = "firm-\(side.rawValue)"
                    case .rejected:
                        verdict = "rejected"
                    }
                    let firstTime = group.members.first?.time ?? imu.timestamp
                    print(String(
                        format: "%.6f s  TAP count=%d verdict=%@ latency=%.3f s id=%@",
                        firstTime,
                        group.members.count,
                        verdict,
                        max(0, imu.timestamp - firstTime),
                        group.eventID(
                            calibrationVersion: stream.classifier.calibration.version
                        )
                    ))
                }
            } catch {
                setError(String(describing: error))
            }
        case .failed(_, let reason):
            setError(reason)
        case .warning(let path, let message):
            let prefix = path.map { "\($0.rawValue): " } ?? ""
            FileHandle.standardError.write(
                Data("warning: \(prefix)\(message)\n".utf8)
            )
        case .completed:
            break
        }
    }

    private func setError(_ reason: String) {
        lock.lock()
        if _sourceError == nil { _sourceError = reason }
        lock.unlock()
    }
}

private final class IMUCaptureController {
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

let toolVersion = "probe-0.1"

private let repositoryRoot: URL = {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}()

let capturesRoot = repositoryRoot.appendingPathComponent("captures", isDirectory: true)

private func collectCaptureEnvironment(requiredPrivileges: [String] = []) -> SessionManifest.Environment {
    var seen: Set<UInt64> = []
    let usages = (try? SPUHardwareInspector.inspect())?.services.compactMap {
        service -> SessionManifest.Environment.HIDUsage? in
        guard let page = service.usagePage, let usage = service.usage else { return nil }
        let key = (UInt64(page) << 32) | UInt64(usage)
        guard seen.insert(key).inserted else { return nil }
        return SessionManifest.Environment.HIDUsage(usagePage: page, usage: usage)
    } ?? []
    return EnvironmentProbe.collect(discoveredUsages: usages, requiredPrivileges: requiredPrivileges)
}

private func jsonString<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    return String(decoding: try encoder.encode(value), as: UTF8.self)
}

private func capabilityDescription(_ state: CapabilityState) -> String {
    switch state {
    case .unknown:
        return "unknown"
    case .available(let detail):
        return "available — \(detail)"
    case .unavailable(let reason):
        return "unavailable — \(reason)"
    case .needsPrivilege(let privilege):
        return "needs privilege — \(privilege)"
    case .needsOptIn:
        return "needs explicit opt-in"
    }
}

private func runIdentify(_ arguments: Arguments) throws {
    let environment = EnvironmentProbe.collect()
    if arguments.has("--json") {
        print(try jsonString(environment))
    } else {
        print(EnvironmentProbe.humanDescription(environment))
    }
}

private func makeCapabilityReport(snapshot: SPUHardwareSnapshot,
                                  displayServices: DisplayServicesStatus) -> CapabilityReport {
    var states: [SensorPath: CapabilityState] = [:]
    states[.spuAccelerometer] = snapshot.state(of: .spuAccelerometer)
    states[.spuGyroscope] = snapshot.state(of: .spuGyroscope)
    states[.spuAmbientLight] = snapshot.state(of: .spuAmbientLight)
    states[.displayServicesAmbientLight] = displayServices.frameworkPresent
        ? .unknown
        : .unavailable(reason: "DisplayServices.framework absent")
    states[.microphone] = .needsOptIn
    states[.camera] = .needsOptIn
    return CapabilityReport(states: states)
}

private func runDiscover(_ arguments: Arguments) throws {
    let snapshot = try SPUHardwareInspector.inspect()
    let displayServices = DisplayServicesProbe.inspect()
    let report = makeCapabilityReport(snapshot: snapshot, displayServices: displayServices)
    if arguments.has("--json") {
        print(try jsonString(report))
        return
    }

    if snapshot.services.isEmpty {
        print("No AppleSPUHIDDriver or AppleSPUHIDDevice services found.")
    } else {
        print("IOKit SPU services (\(snapshot.services.count)):")
        for service in snapshot.services {
            print(service.humanDescription())
        }
    }

    let coreMotion = CoreMotionProbe.accelerometerAvailable()
    print("CoreMotion accelerometer available: \(coreMotion.map(String.init) ?? "unknown (CMMotionManager absent)")")
    print("DisplayServices framework present: \(displayServices.frameworkPresent)")
    print("DisplayServices framework loadable: \(displayServices.frameworkLoadable)")
    print("DisplayServices AggregatedLux: unknown — \(displayServices.detail)")
    print("Capabilities:")
    for path in SensorPath.allCases {
        print("  \(path.rawValue): \(capabilityDescription(report.state(of: path)))")
    }
}

private func median(_ values: [Double]) -> Double? {
    guard !values.isEmpty else { return nil }
    let sorted = values.sorted()
    let middle = sorted.count / 2
    if sorted.count.isMultiple(of: 2) {
        return (sorted[middle - 1] + sorted[middle]) / 2
    }
    return sorted[middle]
}

private func runALSWatch(_ arguments: Arguments) throws {
    let duration = try arguments.double(after: "--duration", default: 30)
    let pollHz = try arguments.double(after: "--poll-hz", default: 20)
    let capture = arguments.has("--capture")
    let panelHints = arguments.has("--panel-hints")
    let label = try arguments.value(after: "--label")
    if capture && label == nil {
        throw ProbeError.usage("--capture requires --label <label>")
    }
    var reportInterval: Int?
    if let raw = try arguments.value(after: "--report-interval") {
        guard let parsed = Int(raw), parsed > 0 else {
            throw ProbeError.usage("--report-interval must be a positive integer (microseconds)")
        }
        reportInterval = parsed
    } else if panelHints {
        reportInterval = 50_000
    }

    let source = try RegistryALSSource(pollHz: pollHz, reportIntervalOverride: reportInterval)
    let dipDetector = panelHints ? try AmbientLightDipDetector() : nil
    var acquisitionParameters = [
        "method": "registry_poll",
        "poll_hz": String(pollHz)
    ]
    if let reportInterval {
        acquisitionParameters["report_interval_override_us"] = String(reportInterval)
    }
    let state = ALSRunState()
    let startedAt = Date()
    var writer: CaptureWriter?
    if capture {
        let captureLabel = label!
        let manifest = SessionManifest(
            label: captureLabel,
            startedAt: startedAt,
            toolVersion: toolVersion,
            environment: collectCaptureEnvironment(),
            sensors: [
                SessionManifest.SensorRecord(
                    path: .spuAmbientLight,
                    file: CaptureFormat.streamFileName(for: .spuAmbientLight),
                    acquisitionParameters: acquisitionParameters
                )
            ]
        )
        writer = try CaptureWriter(
            directory: CaptureWriter.conventionalDirectory(
                under: capturesRoot, label: captureLabel, startedAt: startedAt
            ),
            manifest: manifest
        )
    }

    try source.start { event in
        switch event {
        case .sample(let sample):
            guard case .als(_, let als) = sample else { return }
            state.samples.append(als)
            if state.previousLux == nil || state.previousLux != als.lux {
                print(String(format: "%.6f s  lux=%.6f", als.timestamp, als.lux))
                if state.previousLux != nil { state.changeTimes.append(als.timestamp) }
                state.previousLux = als.lux
            }
            if let writer {
                do {
                    try writer.append(sample)
                } catch {
                    state.writeError = error
                }
            }
            if let dipDetector {
                do {
                    for event in try dipDetector.process(als) {
                        switch event {
                        case .readinessChanged(let readiness):
                            let description: String
                            switch readiness {
                            case .warmingUp: description = "warming-up"
                            case .available: description = "available"
                            case .tooDim: description = "too-dim"
                            }
                            print(String(
                                format: "%.6f s  panel-hint readiness=%@",
                                als.timestamp,
                                description
                            ))
                        case .panelOpenHint(let hint):
                            print(String(
                                format: "%.6f s  PANEL-HINT baseline=%.2f lux=%.2f drop=%.1f%%",
                                hint.timestamp,
                                hint.baselineLux,
                                hint.observedLux,
                                hint.relativeDrop * 100
                            ))
                        }
                    }
                } catch {
                    state.sourceError = String(describing: error)
                }
            }
        case .failed(_, let reason):
            state.sourceError = reason
        case .warning(_, let message):
            FileHandle.standardError.write(Data("warning: \(message)\n".utf8))
        case .completed:
            break
        }
    }

    signal(SIGINT, SIG_IGN)
    let signalSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    signalSource.setEventHandler {
        source.stop()
        exit(130)
    }
    signalSource.resume()

    runLoop(until: ProcessInfo.processInfo.systemUptime + duration) {
        state.writeError != nil || state.sourceError != nil
    }
    signalSource.cancel()
    source.stop()
    if let error = state.writeError { throw error }
    if let error = state.sourceError { throw ProbeError.hardware(error) }

    let values = state.samples.map(\.lux)
    let mean = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    let cadenceIntervals = zip(state.changeTimes.dropFirst(), state.changeTimes)
        .map { $0 - $1 }
    let cadence = median(cadenceIntervals)
    print("Summary:")
    print("  sample count: \(state.samples.count)")
    print("  distinct-value change count: \(state.changeTimes.count)")
    if let minimum = values.min(), let maximum = values.max() {
        print(String(format: "  lux min/max/mean: %.6f / %.6f / %.6f", minimum, maximum, mean))
    } else {
        print("  lux min/max/mean: n/a")
    }
    if let cadence, let fastest = cadenceIntervals.min() {
        print(String(format: "  median seconds between changes: %.6f", cadence))
        print(String(format: "  min seconds between changes: %.6f", fastest))
    } else {
        print("  median seconds between changes: n/a (fewer than two changes)")
    }

    if let writer {
        writer.addLabel(LabelSpan(start: 0, end: duration, label: label!, repetition: 1))
        writer.recordSensorMetadata(
            path: .spuAmbientLight,
            effectiveRateHz: duration > 0 ? Double(state.samples.count) / duration : nil,
            acquisitionParameters: acquisitionParameters
        )
        try writer.finalize()
        print("Capture directory: \(writer.directory.path)")
    }
}

private func runLoop(until deadline: TimeInterval,
                     stopWhen: () -> Bool = { false }) {
    while ProcessInfo.processInfo.systemUptime < deadline && !stopWhen() {
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
    }
}

private func runTapWatch(_ arguments: Arguments) throws {
    let duration = try arguments.double(after: "--duration", default: 30)
    let requestedRate = try arguments.double(after: "--rate-hz", default: 800)
    guard requestedRate <= 10_000 else {
        throw ProbeError.usage("--rate-hz must be between 1 and 10000")
    }
    let reportInterval = Int((1_000_000 / requestedRate).rounded())
    let source = try SPUIMUSource(includeGyroscope: false)
    let processing = SensorProcessingQueue(label: "com.mactivate.tap-watch")
    let state = TapWatchState(stream: try TapStreamClassifier())
    let startedAt = ProcessInfo.processInfo.systemUptime
    defer {
        source.stop()
        processing.finish()
        state.stream.reset()
    }

    do {
        try source.start { event in
            processing.submit {
                state.process(event)
            }
        }
    } catch let error as HardwareError where error.isPrivilegeFailure {
        throw ProbeError.hardware(
            "\(error)\nRerun with: sudo .build/debug/mactuation-probe tap-watch ..."
        )
    }

    signal(SIGINT, SIG_IGN)
    let signalSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    signalSource.setEventHandler {
        source.stop()
        processing.finish()
        exit(130)
    }
    signalSource.resume()

    let deadline = startedAt + duration
    let initialDeadline = min(deadline, startedAt + 1)
    runLoop(until: initialDeadline) {
        source.totalReportCount > 0 ||
            source.malformedReport != nil ||
            state.sourceError != nil
    }
    if source.totalReportCount == 0,
       source.malformedReport == nil,
       state.sourceError == nil,
       ProcessInfo.processInfo.systemUptime < deadline {
        print("No reports arrived without wake properties; applying wake sequence.")
        do {
            try source.applyWakeSequenceIfNeeded(reportInterval: reportInterval)
        } catch let error as HardwareError where error.isPrivilegeFailure {
            throw ProbeError.hardware(
                "\(error)\nRerun with: sudo .build/debug/mactuation-probe tap-watch ..."
            )
        }
    }
    runLoop(until: deadline) {
        source.malformedReport != nil || state.sourceError != nil
    }

    signalSource.cancel()
    source.stop()
    processing.finish()

    if let malformed = source.malformedReport {
        throw ProbeError.hardware("tap watch aborted: \(malformed)")
    }
    if let error = state.sourceError {
        throw ProbeError.hardware("tap watch aborted: \(error)")
    }

    let elapsed = max(
        0.001,
        ProcessInfo.processInfo.systemUptime - startedAt
    )
    let counts = state.counts
    print("Summary:")
    print(String(
        format: "  accelerometer reports: %d (effective %.3f Hz)",
        source.reportCount(for: .spuAccelerometer),
        source.effectiveRate(for: .spuAccelerometer, elapsed: elapsed)
    ))
    if let frozenRate = state.stream.sampleRateHz {
        print(String(format: "  classifier frozen rate: %.3f Hz", frozenRate))
    } else {
        print("  classifier frozen rate: unavailable")
    }
    print("  accepted groups: \(counts.accepted)")
    print("  rejected diagnostic groups: \(counts.rejected)")
}

private func runIMUCapture(_ arguments: Arguments) throws {
    let duration = try arguments.double(after: "--duration", default: 30)
    guard let label = try arguments.value(after: "--label") else {
        throw ProbeError.usage("imu-capture requires --label <label>")
    }
    let rateHz = try arguments.double(after: "--rate-hz", default: 100)
    guard rateHz > 0, rateHz <= 10_000 else {
        throw ProbeError.usage("--rate-hz must be between 1 and 10000")
    }
    let reportInterval = Int((1_000_000 / rateHz).rounded())

    let source = try SPUIMUSource(includeGyroscope: arguments.has("--gyro"))
    let controller = IMUCaptureController(
        source: source,
        label: label,
        markerEnabled: arguments.has("--marker"),
        duration: duration
    )

    do {
        try controller.start()
    } catch let error as HardwareError where error.isPrivilegeFailure {
        throw ProbeError.hardware(
            "\(error)\nRerun with: sudo .build/debug/mactuation-probe imu-capture ..."
        )
    }
    defer { try? controller.finish() }

    signal(SIGINT, SIG_IGN)
    let signalSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    signalSource.setEventHandler {
        do {
            try controller.finish()
        } catch {
            FileHandle.standardError.write(Data("capture finalization failed: \(error)\n".utf8))
        }
        exit(130)
    }
    signalSource.resume()

    var markerSource: DispatchSourceRead?
    if arguments.has("--marker") {
        print("Press Enter to add a 0.5 s marker.")
        let source = DispatchSource.makeReadSource(fileDescriptor: STDIN_FILENO, queue: .main)
        source.setEventHandler {
            var byte: UInt8 = 0
            if read(STDIN_FILENO, &byte, 1) == 1, byte == 10 || byte == 13 {
                controller.addMarker()
            }
        }
        source.resume()
        markerSource = source
    }

    let deadline = controller.startUptime + duration
    let initialDeadline = min(deadline, controller.startUptime + 1.0)
    runLoop(until: initialDeadline) {
        source.totalReportCount > 0 || source.malformedReport != nil
    }
    let missingPaths = source.paths.filter {
        source.reportCount(for: $0) == 0
    }
    if !missingPaths.isEmpty && source.malformedReport == nil &&
        ProcessInfo.processInfo.systemUptime < deadline {
        print(
            "No reports from \(missingPaths.map(\.rawValue).joined(separator: ", ")); " +
                "applying wake sequence."
        )
        do {
            try source.applyWakeSequenceIfNeeded(reportInterval: reportInterval)
        } catch let error as HardwareError where error.isPrivilegeFailure {
            controller.discard()
            throw ProbeError.hardware(
                "\(error)\nRerun with: sudo .build/debug/mactuation-probe imu-capture ..."
            )
        }
    }
    runLoop(until: deadline) {
        source.malformedReport != nil || controller.captureError != nil
    }

    markerSource?.cancel()
    signalSource.cancel()
    try controller.finish()

    if let malformed = source.malformedReport {
        throw ProbeError.capture("capture aborted: \(malformed)")
    }
    if let error = controller.captureError { throw error }
    for path in source.paths {
        let elapsed = max(0.001, ProcessInfo.processInfo.systemUptime - controller.startUptime)
        print(String(
            format: "%@ reports: %d (effective %.3f Hz)",
            path.rawValue,
            source.reportCount(for: path),
            source.effectiveRate(for: path, elapsed: elapsed)
        ))
    }
}

private struct RegionCaptureTrial {
    var side: TapRegionProbeSide
    var intensity: TapRegionProbeIntensity
    var repetition: Int
}

private struct RegionMultiTapTrial {
    var side: TapRegionProbeSide
    var pattern: TapRegionMultiTapPattern
    var repetition: Int
}

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1
        return state
    }
}

private func regionTrials(count: Int, seed: UInt64) -> [RegionCaptureTrial] {
    var trials: [RegionCaptureTrial] = []
    for repetition in 1...count {
        for intensity in TapRegionProbeIntensity.allCases {
            for side in TapRegionProbeSide.allCases {
                trials.append(RegionCaptureTrial(
                    side: side,
                    intensity: intensity,
                    repetition: repetition
                ))
            }
        }
    }
    var generator = SeededGenerator(seed: seed)
    trials.shuffle(using: &generator)
    return trials
}

private func regionMultiTapTrials(
    count: Int,
    seed: UInt64
) -> [RegionMultiTapTrial] {
    var trials: [RegionMultiTapTrial] = []
    for repetition in 1...count {
        for pattern in TapRegionMultiTapPattern.allCases {
            for side in TapRegionProbeSide.allCases {
                trials.append(RegionMultiTapTrial(
                    side: side,
                    pattern: pattern,
                    repetition: repetition
                ))
            }
        }
    }
    var generator = SeededGenerator(seed: seed)
    trials.shuffle(using: &generator)
    return trials
}

private func printRegionMetrics(
    _ title: String,
    metrics: TapRegionQualificationMetrics
) {
    print("\(title):")
    print(String(
        format: "  precision: left %.1f%%  right %.1f%%",
        metrics.leftPrecision * 100,
        metrics.rightPrecision * 100
    ))
    for key in metrics.groupCoverage.keys.sorted() {
        print(String(
            format: "  correct coverage %@: %.1f%%",
            key,
            metrics.groupCoverage[key, default: 0] * 100
        ))
    }
    print(String(
        format: "  classified: %.1f%%  wrong: %d  ambiguous: %d",
        metrics.classifiedFraction * 100,
        metrics.incorrect,
        metrics.ambiguous
    ))
}

private func printRegionFit(
    _ fit: TapRegionThresholdFit,
    validation: [TapRegionProbeObservation]? = nil
) {
    let model = fit.model
    print("Frozen scalar model:")
    print("  feature: \(model.featureName)")
    print(String(
        format: "  %@ below %.8f, ambiguous through %.8f, %@ above",
        model.lowerSide.rawValue,
        model.lowerBoundary,
        model.upperBoundary,
        model.lowerSide == .left ? "right" : "left"
    ))
    printRegionMetrics("Training (feature selection)", metrics: fit.metrics)
    guard let validation else {
        print("Result: exploratory only — collect an independent validation session.")
        return
    }
    let metrics = TapRegionProbeAnalyzer.evaluate(
        model,
        observations: validation
    )
    printRegionMetrics("Independent validation", metrics: metrics)
    print(metrics.qualifies
        ? "Result: PASS — meets 95% precision and 90% per-group coverage gates."
        : "Result: FAIL — do not expose left/right zones with this model.")
}

private func printRegionScreening(
    _ observations: [TapRegionProbeObservation]
) throws {
    let ranked = try TapRegionProbeAnalyzer.rankedFits(observations)
    print("Top scalar feature screens:")
    for fit in ranked.prefix(5) {
        print(String(
            format: "  %@ — precision L %.1f%% R %.1f%%, minimum coverage %.1f%%, wrong %d",
            fit.model.featureName,
            fit.metrics.leftPrecision * 100,
            fit.metrics.rightPrecision * 100,
            fit.metrics.minimumGroupCoverage * 100,
            fit.metrics.incorrect
        ))
    }
    let foldCount = min(
        5,
        Set(observations.map(\.repetition)).count
    )
    guard foldCount >= 2 else {
        print("Held-out screening skipped: at least two repetitions are required.")
        return
    }
    let crossValidation = try TapRegionProbeAnalyzer.crossValidate(
        observations,
        folds: foldCount
    )
    let selectedFeatures = Dictionary(
        grouping: crossValidation.foldModels,
        by: \.featureName
    ).mapValues(\.count)
    printRegionMetrics(
        "\(foldCount)-fold held-out screening",
        metrics: crossValidation.metrics
    )
    print(
        "  selected features by fold: " +
            selectedFeatures.keys.sorted().map {
                "\($0)=\(selectedFeatures[$0, default: 0])"
            }.joined(separator: ", ")
    )

    let linearFits = try TapRegionLinearProbeAnalyzer.rankedFits(observations)
    print("Top regularized linear feature sets:")
    for fit in linearFits.prefix(5) {
        print(String(
            format: "  %@ — precision L %.1f%% R %.1f%%, minimum coverage %.1f%%, wrong %d",
            fit.model.name,
            fit.metrics.leftPrecision * 100,
            fit.metrics.rightPrecision * 100,
            fit.metrics.minimumGroupCoverage * 100,
            fit.metrics.incorrect
        ))
    }
    let linearCrossValidation = try TapRegionLinearProbeAnalyzer.crossValidate(
        observations,
        folds: foldCount
    )
    let selectedLinearModels = Dictionary(
        grouping: linearCrossValidation.foldModels,
        by: \.name
    ).mapValues(\.count)
    printRegionMetrics(
        "\(foldCount)-fold held-out linear screening",
        metrics: linearCrossValidation.metrics
    )
    print(
        "  selected models by fold: " +
            selectedLinearModels.keys.sorted().map {
                "\($0)=\(selectedLinearModels[$0, default: 0])"
            }.joined(separator: ", ")
    )
}

private func printRegionTransferCandidates(
    training: [TapRegionProbeObservation],
    validation: [TapRegionProbeObservation]
) throws {
    let transferred = try TapRegionProbeAnalyzer.rankedFits(training).map {
        (
            fit: $0,
            validation: TapRegionProbeAnalyzer.evaluate(
                $0.model,
                observations: validation
            )
        )
    }.sorted {
        let lhs = [
            $0.validation.qualifies ? 1.0 : 0,
            $0.validation.minimumGroupCoverage,
            min($0.validation.leftPrecision, $0.validation.rightPrecision),
            -Double($0.validation.incorrect)
        ]
        let rhs = [
            $1.validation.qualifies ? 1.0 : 0,
            $1.validation.minimumGroupCoverage,
            min($1.validation.leftPrecision, $1.validation.rightPrecision),
            -Double($1.validation.incorrect)
        ]
        if lhs != rhs {
            return !lhs.lexicographicallyPrecedes(rhs)
        }
        return $0.fit.model.featureName < $1.fit.model.featureName
    }

    print("Frozen pilot-feature transfer ranking:")
    for result in transferred.prefix(5) {
        print(String(
            format: "  %@ — validation precision L %.1f%% R %.1f%%, minimum coverage %.1f%%, wrong %d",
            result.fit.model.featureName,
            result.validation.leftPrecision * 100,
            result.validation.rightPrecision * 100,
            result.validation.minimumGroupCoverage * 100,
            result.validation.incorrect
        ))
    }
}

private func printMultiTapMetrics(
    _ title: String,
    metrics: TapRegionQualificationMetrics
) {
    let displayNames = [
        "left-comfort": "left-double",
        "left-firm": "left-triple",
        "right-comfort": "right-double",
        "right-firm": "right-triple"
    ]
    print("\(title):")
    print(String(
        format: "    precision: left %.1f%%  right %.1f%%",
        metrics.leftPrecision * 100,
        metrics.rightPrecision * 100
    ))
    for key in metrics.groupCoverage.keys.sorted() {
        print(String(
            format: "    correct coverage %@: %.1f%%",
            displayNames[key] ?? key,
            metrics.groupCoverage[key, default: 0] * 100
        ))
    }
    print(String(
        format: "    classified: %.1f%%  wrong: %d  ambiguous: %d",
        metrics.classifiedFraction * 100,
        metrics.incorrect,
        metrics.ambiguous
    ))
}

private func printMultiTapScreening(
    _ gestures: [TapRegionMultiTapGesture]
) throws {
    print(
        "Multi-tap observations: \(gestures.count) gestures, " +
            "\(gestures.reduce(0) { $0 + $1.members.count }) detected impacts"
    )
    for result in try TapRegionMultiTapProbeAnalyzer.screen(gestures) {
        print("Strategy: \(result.name)")
        printMultiTapMetrics(
            "  Training",
            metrics: result.trainingMetrics
        )
        printMultiTapMetrics(
            "  Held-out",
            metrics: result.crossValidationMetrics
        )
        print(
            "    selected features: " +
                result.selectedFeatures.keys.sorted().map {
                    "\($0)=\(result.selectedFeatures[$0, default: 0])"
                }.joined(separator: ", ")
        )
    }
}

private func runRegionAnalysis(_ arguments: Arguments) throws {
    guard let trainingPath = try arguments.value(after: "--training") else {
        throw ProbeError.usage(
            "region-analyze requires --training <capture-directory>"
        )
    }
    let trainingReader = try CaptureReader(
        directory: URL(fileURLWithPath: trainingPath).standardizedFileURL
    )
    var training = try TapRegionProbeAnalyzer.observations(from: trainingReader)
    if let additionalPath = try arguments.value(after: "--training-additional") {
        let additionalReader = try CaptureReader(
            directory: URL(fileURLWithPath: additionalPath).standardizedFileURL
        )
        training += try TapRegionProbeAnalyzer.observations(
            from: additionalReader
        )
    }
    let fit = try TapRegionProbeAnalyzer.fit(training)
    try printRegionScreening(training)

    if let validationPath = try arguments.value(after: "--validation") {
        let validationReader = try CaptureReader(
            directory: URL(fileURLWithPath: validationPath).standardizedFileURL
        )
        let validation = try TapRegionProbeAnalyzer.observations(
            from: validationReader
        )
        try printRegionTransferCandidates(
            training: training,
            validation: validation
        )
        printRegionFit(fit, validation: validation)
    } else {
        printRegionFit(fit)
    }
}

private func runRegionMultiTapAnalysis(_ arguments: Arguments) throws {
    guard let trainingPath = try arguments.value(after: "--training") else {
        throw ProbeError.usage(
            "region-multitap-analyze requires --training <capture-directory>"
        )
    }
    let training = try TapRegionMultiTapProbeAnalyzer.gestures(
        from: CaptureReader(
            directory: URL(fileURLWithPath: trainingPath).standardizedFileURL
        )
    )
    let fitted = try TapRegionMultiTapProbeAnalyzer.fitStrategies(training)
    let validation: [TapRegionMultiTapGesture]?
    if let validationPath = try arguments.value(after: "--validation") {
        validation = try TapRegionMultiTapProbeAnalyzer.gestures(
            from: CaptureReader(
                directory: URL(
                    fileURLWithPath: validationPath
                ).standardizedFileURL
            )
        )
    } else {
        validation = nil
    }

    for strategy in fitted {
        print("Frozen strategy: \(strategy.strategy.name)")
        print("  feature: \(strategy.model.featureName)")
        printMultiTapMetrics(
            "  Training",
            metrics: strategy.trainingMetrics
        )
        if let validation {
            let metrics = TapRegionMultiTapProbeAnalyzer.evaluate(
                strategy,
                gestures: validation
            )
            printMultiTapMetrics("  Independent validation", metrics: metrics)
            print(metrics.qualifies
                ? "  Result: PASS"
                : "  Result: FAIL")
        }
    }
}

private func runRegionCapture(_ arguments: Arguments) throws {
    let count = try arguments.integer(after: "--count", default: 10)
    guard count <= 100 else {
        throw ProbeError.usage("--count must be between 1 and 100")
    }
    let rateHz = try arguments.double(after: "--rate-hz", default: 800)
    guard rateHz <= 10_000 else {
        throw ProbeError.usage("--rate-hz must be between 1 and 10000")
    }
    let seed = UInt64(try arguments.integer(after: "--seed", default: 42))
    let reportInterval = Int((1_000_000 / rateHz).rounded())
    let baselineDuration = 5.0
    let recoveryDuration = 0.75
    let estimatedTrialDuration = 3.0
    let trials = regionTrials(count: count, seed: seed)
    let requestedDuration = 2 + baselineDuration +
        Double(trials.count) * estimatedTrialDuration + 2

    print("Guided left/right palm-region pilot")
    print("  Put the Mac flat on a hard table.")
    print("  Keep both hands off during baseline.")
    print("  Each target remains on screen until a tap is detected.")
    print("  Read it at your own pace, then tap the requested palm-rest side once.")
    print("  The next target appears only after that tap.")
    print("  Comfort = normal easy tap; firm = deliberate but not painful.")
    print("  Trials: \(trials.count) (\(count) per side/force)")
    print("")

    let source = try SPUIMUSource(
        includeGyroscope: true,
        startupReportInterval: reportInterval
    )
    let controller = IMUCaptureController(
        source: source,
        label: "region-pilot",
        markerEnabled: true,
        duration: requestedDuration,
        tapDetectionRateHz: rateHz
    )
    do {
        try controller.start()
    } catch let error as HardwareError where error.isPrivilegeFailure {
        throw ProbeError.hardware(
            "\(error)\nRerun with: sudo .build/debug/mactuation-probe region-capture ..."
        )
    }
    defer { try? controller.finish() }

    signal(SIGINT, SIG_IGN)
    let signalSource = DispatchSource.makeSignalSource(
        signal: SIGINT,
        queue: .main
    )
    signalSource.setEventHandler {
        do {
            try controller.finish()
        } catch {
            FileHandle.standardError.write(
                Data("capture finalization failed: \(error)\n".utf8)
            )
        }
        exit(130)
    }
    signalSource.resume()

    let initialDeadline = controller.startUptime + 1
    runLoop(until: initialDeadline) {
        source.totalReportCount > 0 ||
            source.malformedReport != nil ||
            controller.captureError != nil
    }
    let missingPaths = source.paths.filter {
        source.reportCount(for: $0) == 0
    }
    if !missingPaths.isEmpty,
       source.malformedReport == nil,
       controller.captureError == nil {
        print(
            "No reports from \(missingPaths.map(\.rawValue).joined(separator: ", ")); " +
                "applying wake sequence."
        )
        do {
            try source.applyWakeSequenceIfNeeded(reportInterval: reportInterval)
        } catch let error as HardwareError where error.isPrivilegeFailure {
            controller.discard()
            throw ProbeError.hardware(
                "\(error)\nRerun with: sudo .build/debug/mactuation-probe region-capture ..."
            )
        }
        runLoop(until: ProcessInfo.processInfo.systemUptime + 1) {
            missingPaths.allSatisfy {
                source.reportCount(for: $0) > 0
            } || source.malformedReport != nil ||
                controller.captureError != nil
        }
    }
    let stillMissing = source.paths.filter {
        source.reportCount(for: $0) == 0
    }
    guard stillMissing.isEmpty else {
        controller.discard()
        throw ProbeError.capture(
            "no reports from \(stillMissing.map(\.rawValue).joined(separator: ", ")); " +
                "capture stopped before the tap trials"
        )
    }

    print("HANDS OFF — recording \(Int(baselineDuration)) s baseline...")
    let baselineStart = max(
        0,
        ProcessInfo.processInfo.systemUptime - controller.startUptime
    )
    controller.addRestLabel(
        start: baselineStart,
        end: baselineStart + baselineDuration
    )
    runLoop(
        until: ProcessInfo.processInfo.systemUptime + baselineDuration
    ) {
        source.malformedReport != nil || controller.captureError != nil
    }

    var completed = 0
    for trial in trials {
        if source.malformedReport != nil || controller.captureError != nil {
            break
        }
        completed += 1
        print("")
        print(
            "[\(completed)/\(trials.count)] TARGET: " +
                "\(trial.side.rawValue.uppercased()) · " +
                "\(trial.intensity.rawValue.uppercased())"
        )
        print("          Tap once whenever you are ready...")
        FileHandle.standardOutput.synchronizeFile()
        let armedAfter = controller.latestTapSensorTimestamp
        var candidate: TapEventFeatures?
        while candidate == nil,
              source.malformedReport == nil,
              controller.captureError == nil {
            runLoop(until: ProcessInfo.processInfo.systemUptime + 0.05)
            candidate = controller.consumeTapCandidate(after: armedAfter)
        }
        guard let candidate else { break }
        controller.addRegionMarker(
            side: trial.side,
            intensity: trial.intensity,
            repetition: trial.repetition,
            candidate: candidate
        )
        print(String(
            format: "          Detected at %.3f s (peak %.4f g)",
            candidate.time,
            candidate.peakG
        ))
        FileHandle.standardOutput.synchronizeFile()
        runLoop(
            until: ProcessInfo.processInfo.systemUptime + recoveryDuration
        ) {
            source.malformedReport != nil || controller.captureError != nil
        }
    }

    print("Done. Hands off for 2 s...")
    runLoop(until: ProcessInfo.processInfo.systemUptime + 2)
    signalSource.cancel()
    let directory = controller.captureDirectory
    try controller.finish()

    if let malformed = source.malformedReport {
        throw ProbeError.capture("capture aborted: \(malformed)")
    }
    if let error = controller.captureError { throw error }
    for path in source.paths {
        let elapsed = max(
            0.001,
            ProcessInfo.processInfo.systemUptime - controller.startUptime
        )
        print(String(
            format: "%@ reports: %d (effective %.3f Hz)",
            path.rawValue,
            source.reportCount(for: path),
            source.effectiveRate(for: path, elapsed: elapsed)
        ))
    }
    guard let directory else {
        throw ProbeError.capture("capture directory was not created")
    }
    let observations = try TapRegionProbeAnalyzer.observations(
        from: CaptureReader(directory: directory)
    )
    try printRegionScreening(observations)
    printRegionFit(try TapRegionProbeAnalyzer.fit(observations))
}

private func runRegionMultiTapCapture(_ arguments: Arguments) throws {
    let count = try arguments.integer(after: "--count", default: 10)
    guard count <= 100 else {
        throw ProbeError.usage("--count must be between 1 and 100")
    }
    let rateHz = try arguments.double(after: "--rate-hz", default: 800)
    guard rateHz <= 10_000 else {
        throw ProbeError.usage("--rate-hz must be between 1 and 10000")
    }
    let seed = UInt64(try arguments.integer(after: "--seed", default: 42))
    let reportInterval = Int((1_000_000 / rateHz).rounded())
    let baselineDuration = 5.0
    let recoveryDuration = 0.75
    let trials = regionMultiTapTrials(count: count, seed: seed)
    let requestedDuration = 2 + baselineDuration +
        Double(trials.count) * 5 + 2

    print("Guided left/right multi-tap region study")
    print("  Put the Mac flat on a hard table.")
    print("  Keep both hands off during baseline.")
    print("  Each target remains until the requested gesture is detected.")
    print("  Tap at a natural cadence and consistent force.")
    print("  If the detected count is wrong, the same target will retry.")
    print("  Trials: \(trials.count) (\(count) per side/pattern)")
    print("")

    let source = try SPUIMUSource(
        includeGyroscope: true,
        startupReportInterval: reportInterval
    )
    let controller = IMUCaptureController(
        source: source,
        label: "region-multitap-pilot",
        markerEnabled: true,
        duration: requestedDuration,
        tapDetectionRateHz: rateHz
    )
    do {
        try controller.start()
    } catch let error as HardwareError where error.isPrivilegeFailure {
        throw ProbeError.hardware(
            "\(error)\nRerun with: sudo .build/debug/mactuation-probe " +
                "region-multitap-capture ..."
        )
    }
    defer { try? controller.finish() }

    signal(SIGINT, SIG_IGN)
    let signalSource = DispatchSource.makeSignalSource(
        signal: SIGINT,
        queue: .main
    )
    signalSource.setEventHandler {
        do {
            try controller.finish()
        } catch {
            FileHandle.standardError.write(
                Data("capture finalization failed: \(error)\n".utf8)
            )
        }
        exit(130)
    }
    signalSource.resume()

    let initialDeadline = controller.startUptime + 1
    runLoop(until: initialDeadline) {
        source.totalReportCount > 0 ||
            source.malformedReport != nil ||
            controller.captureError != nil
    }
    let missingPaths = source.paths.filter {
        source.reportCount(for: $0) == 0
    }
    if !missingPaths.isEmpty,
       source.malformedReport == nil,
       controller.captureError == nil {
        print(
            "No reports from \(missingPaths.map(\.rawValue).joined(separator: ", ")); " +
                "applying wake sequence."
        )
        do {
            try source.applyWakeSequenceIfNeeded(reportInterval: reportInterval)
        } catch let error as HardwareError where error.isPrivilegeFailure {
            controller.discard()
            throw ProbeError.hardware(
                "\(error)\nRerun with: sudo .build/debug/mactuation-probe " +
                    "region-multitap-capture ..."
            )
        }
        runLoop(until: ProcessInfo.processInfo.systemUptime + 1) {
            missingPaths.allSatisfy {
                source.reportCount(for: $0) > 0
            } || source.malformedReport != nil ||
                controller.captureError != nil
        }
    }
    let stillMissing = source.paths.filter {
        source.reportCount(for: $0) == 0
    }
    guard stillMissing.isEmpty else {
        controller.discard()
        throw ProbeError.capture(
            "no reports from \(stillMissing.map(\.rawValue).joined(separator: ", ")); " +
                "capture stopped before the multi-tap trials"
        )
    }

    print("HANDS OFF — recording \(Int(baselineDuration)) s baseline...")
    let baselineStart = max(
        0,
        ProcessInfo.processInfo.systemUptime - controller.startUptime
    )
    controller.addRestLabel(
        start: baselineStart,
        end: baselineStart + baselineDuration
    )
    runLoop(
        until: ProcessInfo.processInfo.systemUptime + baselineDuration
    ) {
        source.malformedReport != nil || controller.captureError != nil
    }

    var completed = 0
    for trial in trials {
        if source.malformedReport != nil || controller.captureError != nil {
            break
        }
        completed += 1
        print("")
        print(
            "[\(completed)/\(trials.count)] TARGET: " +
                "\(trial.side.rawValue.uppercased()) · " +
                "\(trial.pattern.rawValue.uppercased())"
        )

        var matchedGroup: TapGroup?
        var attempt = 0
        while matchedGroup == nil,
              source.malformedReport == nil,
              controller.captureError == nil {
            attempt += 1
            print(
                attempt == 1
                    ? "          Perform the gesture whenever you are ready..."
                    : "          Retry the same gesture whenever you are ready..."
            )
            FileHandle.standardOutput.synchronizeFile()
            let armedAfter = controller.latestTapSensorTimestamp
            var group: TapGroup?
            while group == nil,
                  source.malformedReport == nil,
                  controller.captureError == nil {
                runLoop(until: ProcessInfo.processInfo.systemUptime + 0.05)
                group = controller.consumeTapGroup(after: armedAfter)
            }
            guard let group else { break }
            if group.members.count == trial.pattern.memberCount {
                matchedGroup = group
            } else {
                print(
                    "          Detected \(group.members.count) impact" +
                        "\(group.members.count == 1 ? "" : "s"); expected " +
                        "\(trial.pattern.memberCount)."
                )
                runLoop(
                    until: ProcessInfo.processInfo.systemUptime +
                        recoveryDuration
                )
            }
        }
        guard let group = matchedGroup else { break }
        controller.addRegionMultiTapLabels(
            side: trial.side,
            pattern: trial.pattern,
            repetition: trial.repetition,
            group: group
        )
        let peaks = group.members.map {
            String(format: "%.4f", $0.peakG)
        }.joined(separator: ", ")
        print(
            "          Detected \(group.members.count) taps " +
                "(peaks \(peaks) g)"
        )
        FileHandle.standardOutput.synchronizeFile()
        runLoop(
            until: ProcessInfo.processInfo.systemUptime + recoveryDuration
        ) {
            source.malformedReport != nil || controller.captureError != nil
        }
    }

    print("Done. Hands off for 2 s...")
    runLoop(until: ProcessInfo.processInfo.systemUptime + 2)
    signalSource.cancel()
    let directory = controller.captureDirectory
    try controller.finish()

    if let malformed = source.malformedReport {
        throw ProbeError.capture("capture aborted: \(malformed)")
    }
    if let error = controller.captureError { throw error }
    for path in source.paths {
        let elapsed = max(
            0.001,
            ProcessInfo.processInfo.systemUptime - controller.startUptime
        )
        print(String(
            format: "%@ reports: %d (effective %.3f Hz)",
            path.rawValue,
            source.reportCount(for: path),
            source.effectiveRate(for: path, elapsed: elapsed)
        ))
    }
    guard let directory else {
        throw ProbeError.capture("capture directory was not created")
    }
    let gestures = try TapRegionMultiTapProbeAnalyzer.gestures(
        from: CaptureReader(directory: directory)
    )
    try printMultiTapScreening(gestures)
}

private func usage() -> String {
    """
    Usage:
      mactuation-probe identify [--json]
      mactuation-probe discover [--json]
      mactuation-probe als-watch [--duration seconds] [--poll-hz hz] [--report-interval us] [--panel-hints] [--capture --label label]
      mactuation-probe tap-watch [--duration seconds] [--rate-hz hz]
      mactuation-probe imu-capture [--duration seconds] --label label [--rate-hz hz] [--gyro] [--marker]
      mactuation-probe region-capture [--count per-side-force] [--rate-hz hz] [--seed integer]
      mactuation-probe region-multitap-capture [--count per-side-pattern] [--rate-hz hz] [--seed integer]
      mactuation-probe region-multitap-analyze --training capture-directory [--validation capture-directory]
      mactuation-probe region-analyze --training capture-directory [--training-additional capture-directory] [--validation capture-directory]
    """
}

do {
    let raw = Array(CommandLine.arguments.dropFirst())
    guard let command = raw.first else {
        throw ProbeError.usage(usage())
    }
    let arguments = Arguments(values: Array(raw.dropFirst()))
    switch command {
    case "identify":
        try runIdentify(arguments)
    case "discover":
        try runDiscover(arguments)
    case "als-watch":
        try runALSWatch(arguments)
    case "tap-watch":
        try runTapWatch(arguments)
    case "imu-capture":
        try runIMUCapture(arguments)
    case "region-capture":
        try runRegionCapture(arguments)
    case "region-multitap-capture":
        try runRegionMultiTapCapture(arguments)
    case "region-multitap-analyze":
        try runRegionMultiTapAnalysis(arguments)
    case "region-analyze":
        try runRegionAnalysis(arguments)
    case "help", "--help", "-h":
        print(usage())
    default:
        throw ProbeError.usage("unknown subcommand: \(command)\n\(usage())")
    }
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
