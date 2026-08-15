import Darwin
import Foundation

let toolVersion = "probe-0.1"

private let repositoryRoot: URL = {
    var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while directory.path != "/" {
        if FileManager.default.fileExists(
            atPath: directory.appendingPathComponent(".git").path
        ) {
            return directory
        }
        directory.deleteLastPathComponent()
    }
    preconditionFailure("repository root not found from \(#filePath)")
}()

let capturesRoot = repositoryRoot.appendingPathComponent("captures", isDirectory: true)

func usage() -> String {
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
