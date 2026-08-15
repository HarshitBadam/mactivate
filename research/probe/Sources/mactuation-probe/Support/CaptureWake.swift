import Darwin
import Foundation
import MactuationCore
import MactuationHardware

func startCapture(_ controller: IMUCaptureController, command: String) throws {
    do {
        try controller.start()
    } catch let error as HardwareError where error.isPrivilegeFailure {
        throw privilegeRerunError(error, command: command)
    }
}

func installCaptureInterruptHandler(
    _ controller: IMUCaptureController
) -> DispatchSourceSignal {
    signal(SIGINT, SIG_IGN)
    let signalSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
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
    return signalSource
}

func applyWakeIfNeeded(
    source: SPUIMUSource,
    reportInterval: Int,
    command: String,
    discard: IMUCaptureController? = nil
) throws {
    do {
        try source.applyWakeSequenceIfNeeded(reportInterval: reportInterval)
    } catch let error as HardwareError where error.isPrivilegeFailure {
        discard?.discard()
        throw privilegeRerunError(error, command: command)
    }
}

func printCaptureRates(source: SPUIMUSource, startUptime: TimeInterval) {
    for path in source.paths {
        let elapsed = max(
            0.001,
            ProcessInfo.processInfo.systemUptime - startUptime
        )
        print(String(
            format: "%@ reports: %d (effective %.3f Hz)",
            path.rawValue,
            source.reportCount(for: path),
            source.effectiveRate(for: path, elapsed: elapsed)
        ))
    }
}

func throwIfCaptureAborted(
    source: SPUIMUSource,
    controller: IMUCaptureController
) throws {
    if let malformed = source.malformedReport {
        throw ProbeError.capture("capture aborted: \(malformed)")
    }
    if let error = controller.captureError { throw error }
}

func captureFailed(source: SPUIMUSource, controller: IMUCaptureController) -> Bool {
    source.malformedReport != nil || controller.captureError != nil
}

func prepareGuidedCapture(
    source: SPUIMUSource,
    controller: IMUCaptureController,
    reportInterval: Int,
    command: String,
    trialDescription: String
) throws {
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
        try applyWakeIfNeeded(
            source: source,
            reportInterval: reportInterval,
            command: command,
            discard: controller
        )
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
                "capture stopped before the \(trialDescription)"
        )
    }
}

func recordGuidedBaseline(
    source: SPUIMUSource,
    controller: IMUCaptureController,
    duration: TimeInterval
) {
    print("HANDS OFF — recording \(Int(duration)) s baseline...")
    let baselineStart = max(
        0,
        ProcessInfo.processInfo.systemUptime - controller.startUptime
    )
    controller.addRestLabel(
        start: baselineStart,
        end: baselineStart + duration
    )
    runLoop(
        until: ProcessInfo.processInfo.systemUptime + duration
    ) {
        source.malformedReport != nil || controller.captureError != nil
    }
}

func finishGuidedCapture(
    source: SPUIMUSource,
    controller: IMUCaptureController,
    signalSource: DispatchSourceSignal
) throws -> URL {
    print("Done. Hands off for 2 s...")
    runLoop(until: ProcessInfo.processInfo.systemUptime + 2)
    signalSource.cancel()
    let directory = controller.captureDirectory
    try controller.finish()
    try throwIfCaptureAborted(source: source, controller: controller)
    printCaptureRates(source: source, startUptime: controller.startUptime)
    guard let directory else {
        throw ProbeError.capture("capture directory was not created")
    }
    return directory
}
