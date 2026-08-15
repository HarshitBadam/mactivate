import Foundation
import MactuationCapture
import MactuationCore
import MactuationHardware
import MactuationResearch

func runRegionMultiTapCapture(_ arguments: Arguments) throws {
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
    try startCapture(controller, command: "region-multitap-capture")
    defer { try? controller.finish() }

    let signalSource = installCaptureInterruptHandler(controller)
    try prepareGuidedCapture(
        source: source,
        controller: controller,
        reportInterval: reportInterval,
        command: "region-multitap-capture",
        trialDescription: "multi-tap trials"
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

    let directory = try finishGuidedCapture(
        source: source,
        controller: controller,
        signalSource: signalSource
    )
    let gestures = try TapRegionMultiTapProbeAnalyzer.gestures(
        from: CaptureReader(directory: directory)
    )
    try printMultiTapScreening(gestures)
}
