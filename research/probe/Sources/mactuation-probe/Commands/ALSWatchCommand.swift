import Darwin
import Foundation
import MactuationCapture
import MactuationCore
import MactuationHardware

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

private func median(_ values: [Double]) -> Double? {
    guard !values.isEmpty else { return nil }
    let sorted = values.sorted()
    let middle = sorted.count / 2
    if sorted.count.isMultiple(of: 2) {
        return (sorted[middle - 1] + sorted[middle]) / 2
    }
    return sorted[middle]
}

func runALSWatch(_ arguments: Arguments) throws {
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
