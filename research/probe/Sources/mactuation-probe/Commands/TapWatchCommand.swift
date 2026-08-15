import Darwin
import Foundation
import MactuationCore
import MactuationHardware

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

func runTapWatch(_ arguments: Arguments) throws {
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
        throw privilegeRerunError(error, command: "tap-watch")
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
        try applyWakeIfNeeded(
            source: source,
            reportInterval: reportInterval,
            command: "tap-watch"
        )
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
