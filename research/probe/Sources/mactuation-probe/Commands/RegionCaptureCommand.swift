import Foundation
import MactuationCapture
import MactuationCore
import MactuationHardware
import MactuationResearch

func runRegionCapture(_ arguments: Arguments) throws {
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
    try startCapture(controller, command: "region-capture")
    defer { try? controller.finish() }

    let signalSource = installCaptureInterruptHandler(controller)
    try prepareGuidedCapture(
        source: source,
        controller: controller,
        reportInterval: reportInterval,
        command: "region-capture",
        trialDescription: "tap trials"
    )
    recordGuidedBaseline(
        source: source,
        controller: controller,
        duration: baselineDuration
    )

    var completed = 0
    for trial in trials {
        if captureFailed(source: source, controller: controller) {
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

    let directory = try finishGuidedCapture(
        source: source,
        controller: controller,
        signalSource: signalSource
    )
    let observations = try TapRegionProbeAnalyzer.observations(
        from: CaptureReader(directory: directory)
    )
    try printRegionScreening(observations)
    printRegionFit(try TapRegionProbeAnalyzer.fit(observations))
}
