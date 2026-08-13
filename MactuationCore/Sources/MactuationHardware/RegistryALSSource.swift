import Foundation
import IOKit
import MactuationCore

public final class RegistryALSSource: SensorSource {
    public let paths: [SensorPath] = [.spuAmbientLight]

    private let service: SPURegistryService
    private let pollHz: Double
    private let reportIntervalOverride: Int?
    private let queue = DispatchQueue(
        label: "com.mactivate.registry-als",
        qos: .utility
    )
    private let queueKey = DispatchSpecificKey<Void>()
    private let lock = NSLock()
    private var savedReportInterval: NSNumber?
    private var writtenReportInterval: NSNumber?
    private var timer: DispatchSourceTimer?
    private var eventHandler: ((SensorSourceEvent) -> Void)?
    private var startUptime: TimeInterval = 0
    private var running = false

    public init(pollHz: Double, reportIntervalOverride: Int? = nil) throws {
        guard pollHz.isFinite, pollHz > 0 else {
            throw HardwareError.invalidConfiguration("pollHz must be greater than zero")
        }
        if let reportIntervalOverride, reportIntervalOverride <= 0 {
            throw HardwareError.invalidConfiguration(
                "report interval must be a positive number of microseconds"
            )
        }
        guard let service = try SPURegistry.driver(usagePage: 0xFF00, usage: 4) else {
            throw SensorSourceError.pathUnavailable(
                .spuAmbientLight,
                reason: "Apple SPU ALS 0xFF00/4 is absent"
            )
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
        queue.setSpecific(key: queueKey, value: ())
    }

    deinit {
        stop()
    }

    public func readLux() throws -> Double {
        guard let value = service.number("CurrentLux") else {
            throw SensorSourceError.pathUnavailable(
                .spuAmbientLight,
                reason: "CurrentLux disappeared or became unreadable"
            )
        }
        return value.doubleValue
    }

    public func start(handler: @escaping (SensorSourceEvent) -> Void) throws {
        try lock.withLock {
            guard !running else { throw SensorSourceError.alreadyStarted }
            try applyReportIntervalOverrideIfRequested()
            eventHandler = handler
            startUptime = ProcessInfo.processInfo.systemUptime
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(
                deadline: .now(),
                repeating: 1.0 / pollHz,
                leeway: .milliseconds(1)
            )
            timer.setEventHandler { [weak self] in
                self?.poll()
            }
            self.timer = timer
            running = true
            timer.resume()
        }
    }

    public func stop() {
        let state: (DispatchSourceTimer, (SensorSourceEvent) -> Void)? =
            lock.withLock {
                guard running, let timer, let eventHandler else { return nil }
                running = false
                self.timer = nil
                return (timer, eventHandler)
            }
        guard let (timer, handler) = state else { return }
        timer.setEventHandler {}
        timer.cancel()

        let finish = {
            self.restoreReportIntervalIfNeeded(handler: handler)
            handler(.completed)
            self.lock.withLock { self.eventHandler = nil }
        }
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            finish()
        } else {
            queue.sync(execute: finish)
        }
    }

    private func poll() {
        do {
            let value = try readLux()
            let timestamp = ProcessInfo.processInfo.systemUptime - startUptime
            currentHandler()?(.sample(.als(
                path: .spuAmbientLight,
                sample: ALSSample(timestamp: timestamp, lux: value)
            )))
        } catch {
            failFromQueue(error)
        }
    }

    private func failFromQueue(_ error: Error) {
        let state: (DispatchSourceTimer, (SensorSourceEvent) -> Void)? =
            lock.withLock {
                guard running, let timer, let eventHandler else { return nil }
                running = false
                self.timer = nil
                return (timer, eventHandler)
            }
        guard let (timer, handler) = state else { return }
        timer.setEventHandler {}
        timer.cancel()
        handler(.failed(path: .spuAmbientLight, reason: String(describing: error)))
        restoreReportIntervalIfNeeded(handler: handler)
        lock.withLock { eventHandler = nil }
    }

    private func applyReportIntervalOverrideIfRequested() throws {
        guard let override = reportIntervalOverride else { return }
        guard let saved = service.number("ReportInterval") else {
            throw HardwareError.invalidConfiguration(
                "cannot override ALS ReportInterval without a readable original value"
            )
        }
        let written = NSNumber(value: override)
        let result = service.setProperty("ReportInterval", value: written)
        guard result == KERN_SUCCESS else {
            throw HardwareError.propertySetFailed(
                path: .spuAmbientLight,
                key: "ReportInterval",
                result: result
            )
        }
        savedReportInterval = saved
        writtenReportInterval = written
    }

    private func restoreReportIntervalIfNeeded(
        handler: (SensorSourceEvent) -> Void
    ) {
        guard let saved = savedReportInterval,
              writtenReportInterval != nil else { return }
        savedReportInterval = nil
        writtenReportInterval = nil
        if service.property("ReportInterval", equals: saved) {
            return
        }
        // The VD6286 normalizes a requested 50,000 µs interval to its
        // approximately 97,000 µs physical floor, so equality with the value
        // written by this process is not a reliable ownership check here.
        let result = service.setProperty("ReportInterval", value: saved)
        if result != KERN_SUCCESS {
            handler(.warning(
                path: .spuAmbientLight,
                message: "failed to restore ReportInterval: \(ioResult(result))"
            ))
        }
    }

    private func currentHandler() -> ((SensorSourceEvent) -> Void)? {
        lock.withLock { eventHandler }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
