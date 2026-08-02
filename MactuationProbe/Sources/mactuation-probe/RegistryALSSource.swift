import Darwin
import Foundation
import MactuationCore

final class RegistryALSSource: SensorSource {
    let paths: [SensorPath] = [.spuAmbientLight]

    private let service: SPURegistryService
    private let pollHz: Double
    private let reportIntervalOverride: Int?
    private var savedReportInterval: NSNumber?
    private let queue = DispatchQueue(label: "mactuation.probe.registry-als")
    private var timer: DispatchSourceTimer?
    private var startUptime: TimeInterval = 0

    init(pollHz: Double, reportIntervalOverride: Int? = nil) throws {
        guard pollHz.isFinite, pollHz > 0 else {
            throw ProbeError.usage("--poll-hz must be greater than zero")
        }
        guard let service = try SPURegistry.driver(usagePage: 0xFF00, usage: 4) else {
            throw SensorSourceError.pathUnavailable(.spuAmbientLight,
                                                    reason: "Apple SPU ALS 0xFF00/4 is absent")
        }
        guard service.number("CurrentLux") != nil else {
            throw SensorSourceError.pathUnavailable(
                .spuAmbientLight,
                reason: "\(service.className) is present but CurrentLux is not readable"
            )
        }
        self.service = service
        self.pollHz = pollHz
        self.reportIntervalOverride = reportIntervalOverride
    }

    func readLux() throws -> Double {
        guard let value = service.number("CurrentLux") else {
            throw SensorSourceError.pathUnavailable(
                .spuAmbientLight,
                reason: "CurrentLux disappeared or became unreadable"
            )
        }
        return value.doubleValue
    }

    func start(handler: @escaping (SensorSample) -> Void) throws {
        guard timer == nil else { throw SensorSourceError.alreadyStarted }
        try applyReportIntervalOverrideIfRequested()
        startUptime = ProcessInfo.processInfo.systemUptime
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 1.0 / pollHz, leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in
            guard let self, let value = try? self.readLux() else { return }
            let timestamp = ProcessInfo.processInfo.systemUptime - self.startUptime
            handler(.als(path: .spuAmbientLight,
                         sample: ALSSample(timestamp: timestamp, lux: value)))
        }
        self.timer = timer
        timer.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
        queue.sync {}
        restoreReportIntervalIfNeeded()
    }

    private func applyReportIntervalOverrideIfRequested() throws {
        guard let override = reportIntervalOverride else { return }
        let saved = service.number("ReportInterval")
        let result = service.setProperty("ReportInterval", value: NSNumber(value: override))
        guard result == KERN_SUCCESS else {
            throw ProbeError.hardware(
                "setting ReportInterval=\(override) on \(service.className) failed: \(ioResult(result))"
            )
        }
        savedReportInterval = saved
        let previous = saved.map { "\($0)" } ?? "unknown"
        FileHandle.standardError.write(Data(
            "ReportInterval override: \(override) us (was \(previous) us); restoring on exit\n".utf8
        ))
    }

    private func restoreReportIntervalIfNeeded() {
        guard let saved = savedReportInterval else { return }
        savedReportInterval = nil
        let result = service.setProperty("ReportInterval", value: saved)
        if result == KERN_SUCCESS {
            FileHandle.standardError.write(Data("ReportInterval restored to \(saved) us\n".utf8))
        } else {
            FileHandle.standardError.write(Data(
                "warning: failed to restore ReportInterval=\(saved): \(ioResult(result))\n".utf8
            ))
        }
    }
}
