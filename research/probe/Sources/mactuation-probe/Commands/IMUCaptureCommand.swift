import Darwin
import Foundation
import MactuationCore
import MactuationHardware

func runIMUCapture(_ arguments: Arguments) throws {
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

    try startCapture(controller, command: "imu-capture")
    defer { try? controller.finish() }

    let signalSource = installCaptureInterruptHandler(controller)

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
        try applyWakeIfNeeded(
            source: source,
            reportInterval: reportInterval,
            command: "imu-capture",
            discard: controller
        )
    }
    runLoop(until: deadline) {
        source.malformedReport != nil || controller.captureError != nil
    }

    markerSource?.cancel()
    signalSource.cancel()
    try controller.finish()

    try throwIfCaptureAborted(source: source, controller: controller)
    printCaptureRates(source: source, startUptime: controller.startUptime)
}
