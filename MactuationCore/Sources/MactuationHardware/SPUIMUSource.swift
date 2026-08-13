import CoreFoundation
import Foundation
import IOKit
import IOKit.hid
import MactuationCore

private final class IMUChannel {
    weak var owner: SPUIMUSource?
    let path: SensorPath
    let device: IOHIDDevice
    let reportBuffer: UnsafeMutablePointer<UInt8>
    let reportBufferLength: Int

    init(owner: SPUIMUSource, path: SensorPath, device: IOHIDDevice,
         reportBufferLength: Int) {
        self.owner = owner
        self.path = path
        self.device = device
        self.reportBufferLength = reportBufferLength
        reportBuffer = .allocate(capacity: reportBufferLength)
        reportBuffer.initialize(repeating: 0, count: reportBufferLength)
    }

    deinit {
        reportBuffer.deinitialize(count: reportBufferLength)
        reportBuffer.deallocate()
    }
}

private final class StartHandshake {
    let semaphore = DispatchSemaphore(value: 0)
    var result: Result<Void, Error>?
}

private final class ResultBox<Value> {
    var result: Result<Value, Error>?
}

private func imuInputReportCallback(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    type: IOHIDReportType,
    reportID: UInt32,
    report: UnsafeMutablePointer<UInt8>,
    reportLength: CFIndex
) {
    guard let context else { return }
    let channel = Unmanaged<IMUChannel>.fromOpaque(context).takeUnretainedValue()
    channel.owner?.receive(
        channel: channel,
        result: result,
        report: report,
        length: Int(reportLength)
    )
}

public final class SPUIMUSource: SensorSource {
    public let paths: [SensorPath]

    private let lifecycleLock = NSLock()
    private let statisticsLock = NSLock()
    private let registryServices: [SensorPath: SPURegistryService]
    private let deviceServices: [SensorPath: SPURegistryService]
    private var channels: [IMUChannel] = []
    private var eventHandler: ((SensorSourceEvent) -> Void)?
    private var workerThread: Thread?
    private var workerRunLoop: CFRunLoop?
    private var running = false
    private var startUptime: TimeInterval = 0

    private var reportCounts: [SensorPath: Int] = [:]
    private var firstSampleTimes: [SensorPath: TimeInterval] = [:]
    private var lastSampleTimes: [SensorPath: TimeInterval] = [:]
    private var firstLengths: [SensorPath: Int] = [:]
    private var firstHex: [SensorPath: String] = [:]
    private var oddLengthCounts: [SensorPath: Int] = [:]
    private var callbackErrorCounts: [SensorPath: Int] = [:]
    private var reportedCallbackFailures: Set<SensorPath> = []
    private var malformedMessage: String?
    private var savedProperties: [SensorPath: [String: AnyObject]] = [:]
    private var writtenProperties: [SensorPath: [String: AnyObject]] = [:]
    private var changedProperties: [SensorPath: [String]] = [:]
    private var _wakeRequired = false
    private var _wakePropertiesSet: [String] = []
    private var _reportIntervalUsed: Int?

    public init(includeGyroscope: Bool) throws {
        var requested: [SensorPath] = [.spuAccelerometer]
        if includeGyroscope { requested.append(.spuGyroscope) }
        let discovered = try SPURegistry.discover()
        var drivers: [SensorPath: SPURegistryService] = [:]
        var devices: [SensorPath: SPURegistryService] = [:]
        for path in requested {
            let usage: UInt32 = path == .spuAccelerometer ? 3 : 9
            guard let driver = discovered.first(where: {
                $0.className != "AppleSPUHIDDevice" &&
                    $0.usagePage == 0xFF00 && $0.usage == usage
            }), let device = discovered.first(where: {
                $0.className == "AppleSPUHIDDevice" &&
                    $0.usagePage == 0xFF00 && $0.usage == usage
            }) else {
                throw HardwareError.deviceAbsent(path)
            }
            drivers[path] = driver
            devices[path] = device
        }
        paths = requested
        registryServices = drivers
        deviceServices = devices
    }

    deinit {
        stop()
    }

    public func start(handler: @escaping (SensorSourceEvent) -> Void) throws {
        let handshake = StartHandshake()
        let thread: Thread = try lifecycleLock.withLock {
            guard !running else { throw SensorSourceError.alreadyStarted }
            running = true
            eventHandler = handler
            startUptime = ProcessInfo.processInfo.systemUptime
            resetStatistics()

            let thread = Thread { [weak self, handshake] in
                do {
                    guard let runLoop = CFRunLoopGetCurrent() else {
                        throw HardwareError.registry("could not create IMU worker RunLoop")
                    }
                    guard let source = self else {
                        throw HardwareError.registry("IMU source was released during startup")
                    }
                    try source.prepareWorker(on: runLoop)
                    handshake.result = .success(())
                } catch {
                    handshake.result = .failure(error)
                }
                handshake.semaphore.signal()

                guard case .success? = handshake.result else { return }
                CFRunLoopRun()
                if let runLoop = CFRunLoopGetCurrent() {
                    self?.handleUnexpectedWorkerExit(on: runLoop)
                }
            }
            thread.name = "com.mactivate.spu-imu-runloop"
            workerThread = thread
            return thread
        }

        thread.start()
        handshake.semaphore.wait()
        guard let result = handshake.result else {
            throw HardwareError.registry("IMU worker did not report startup state")
        }
        do {
            try result.get()
        } catch {
            lifecycleLock.withLock {
                running = false
                eventHandler = nil
                workerThread = nil
                workerRunLoop = nil
            }
            throw error
        }
    }

    public func stop() {
        let state: (CFRunLoop, Thread, (SensorSourceEvent) -> Void)? =
            lifecycleLock.withLock {
                guard running, let runLoop = workerRunLoop,
                      let thread = workerThread, let handler = eventHandler else {
                    return nil
                }
                running = false
                return (runLoop, thread, handler)
            }
        guard let (runLoop, thread, handler) = state else { return }

        let cleanup = {
            self.closeDevices(on: runLoop)
            self.restoreProperties()
            handler(.completed)
            self.lifecycleLock.withLock {
                self.eventHandler = nil
                self.workerRunLoop = nil
                self.workerThread = nil
            }
            CFRunLoopStop(runLoop)
        }

        if Thread.current === thread {
            cleanup()
            return
        }
        let semaphore = DispatchSemaphore(value: 0)
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) {
            cleanup()
            semaphore.signal()
        }
        CFRunLoopWakeUp(runLoop)
        semaphore.wait()
    }

    public func applyWakeSequenceIfNeeded(reportInterval: Int = 10_000) throws {
        guard reportInterval > 0 else {
            throw HardwareError.invalidConfiguration(
                "report interval must be a positive number of microseconds"
            )
        }
        try performOnWorker {
            guard self.totalReportCount == 0 else { return }
            self.statisticsLock.withLock { self._wakeRequired = true }

            let desired: [(String, AnyObject)] = [
                ("SensorPropertyReportingState", NSNumber(value: Int32(1))),
                ("SensorPropertyPowerState", NSNumber(value: Int32(1))),
                ("ReportInterval", NSNumber(value: Int32(reportInterval)))
            ]

            for path in self.paths {
                guard let service = self.registryServices[path] else { continue }
                var snapshots: [String: AnyObject] = [:]
                for (key, _) in desired {
                    if let value = service.property(key) {
                        snapshots[key] = value
                    } else if key == "ReportInterval" {
                        self.restoreProperties()
                        throw HardwareError.wakeFailed(
                            "\(path.rawValue) has no readable pre-existing ReportInterval"
                        )
                    } else {
                        snapshots[key] = NSNumber(value: Int32(0))
                    }
                }
                self.savedProperties[path] = snapshots

                for (key, value) in desired {
                    let result = service.setProperty(key, value: value)
                    guard result == KERN_SUCCESS else {
                        self.restoreProperties()
                        throw HardwareError.propertySetFailed(
                            path: path, key: key, result: result
                        )
                    }
                    self.changedProperties[path, default: []].append(key)
                    self.writtenProperties[path, default: [:]][key] = value
                    self.statisticsLock.withLock {
                        if !self._wakePropertiesSet.contains(key) {
                            self._wakePropertiesSet.append(key)
                        }
                    }
                }
            }
            self.statisticsLock.withLock {
                self._reportIntervalUsed = reportInterval
            }
        }
    }

    public var wakeRequired: Bool {
        statisticsLock.withLock { _wakeRequired }
    }

    public var wakePropertiesSet: [String] {
        statisticsLock.withLock { _wakePropertiesSet }
    }

    public var reportIntervalUsed: Int? {
        statisticsLock.withLock { _reportIntervalUsed }
    }

    public var totalReportCount: Int {
        statisticsLock.withLock { reportCounts.values.reduce(0, +) }
    }

    public func reportCount(for path: SensorPath) -> Int {
        statisticsLock.withLock { reportCounts[path, default: 0] }
    }

    public func effectiveRate(for path: SensorPath, elapsed: TimeInterval) -> Double {
        statisticsLock.withLock {
            let count = reportCounts[path, default: 0]
            if count > 1, let first = firstSampleTimes[path], let last = lastSampleTimes[path],
               last > first {
                return Double(count - 1) / (last - first)
            }
            guard elapsed > 0 else { return 0 }
            return Double(count) / elapsed
        }
    }

    public var malformedReport: String? {
        statisticsLock.withLock { malformedMessage }
    }

    public func firstReportLength(for path: SensorPath) -> Int? {
        statisticsLock.withLock { firstLengths[path] }
    }

    public func anomalies(for path: SensorPath) -> [String] {
        statisticsLock.withLock {
            var values: [String] = []
            let odd = oddLengthCounts[path, default: 0]
            let errors = callbackErrorCounts[path, default: 0]
            if odd > 0 {
                values.append("\(odd) reports differed from the first report length")
            }
            if errors > 0 {
                values.append("\(errors) callbacks returned non-success IOReturn")
            }
            if reportCounts[path, default: 0] == 0 {
                values.append("no input reports received")
            }
            return values
        }
    }

    fileprivate func receive(channel: IMUChannel, result: IOReturn,
                             report: UnsafeMutablePointer<UInt8>, length: Int) {
        let path = channel.path
        if result != kIOReturnSuccess {
            let shouldReport = statisticsLock.withLock {
                callbackErrorCounts[path, default: 0] += 1
                return reportedCallbackFailures.insert(path).inserted
            }
            if shouldReport {
                emit(.failed(
                    path: path,
                    reason: "HID report callback failed with \(ioResult(result))"
                ))
            }
            return
        }

        var shouldReportMalformed = false
        statisticsLock.withLock {
            if firstLengths[path] == nil {
                firstLengths[path] = length
                let bytes = UnsafeBufferPointer(start: report, count: max(0, length))
                firstHex[path] = bytes.map { String(format: "%02x", $0) }.joined()
                if length < SPUIMUReportDecoder.minimumLength {
                    malformedMessage =
                        "\(path.rawValue) first report was \(length) bytes " +
                        "(<\(SPUIMUReportDecoder.minimumLength)); " +
                        "hex=\(firstHex[path] ?? "")"
                    shouldReportMalformed = true
                }
            } else if firstLengths[path] != length {
                oddLengthCounts[path, default: 0] += 1
            }
        }
        guard !shouldReportMalformed else {
            emit(.failed(path: path, reason: malformedReport ?? "malformed IMU report"))
            return
        }

        let bytes = UnsafeBufferPointer(start: report, count: max(0, length))
        guard let decoded = SPUIMUReportDecoder.decode(bytes) else { return }
        let timestamp = ProcessInfo.processInfo.systemUptime - startUptime
        statisticsLock.withLock {
            reportCounts[path, default: 0] += 1
            if firstSampleTimes[path] == nil { firstSampleTimes[path] = timestamp }
            lastSampleTimes[path] = timestamp
        }
        emit(.sample(.imu(
            path: path,
            sample: IMUSample(
                timestamp: timestamp,
                x: decoded.x,
                y: decoded.y,
                z: decoded.z
            )
        )))
    }

    private func prepareWorker(on runLoop: CFRunLoop) throws {
        lifecycleLock.withLock { workerRunLoop = runLoop }
        do {
            for path in paths {
                guard let service = deviceServices[path],
                      let device = IOHIDDeviceCreate(kCFAllocatorDefault, service.entry) else {
                    throw HardwareError.deviceAbsent(path)
                }
                let openResult = IOHIDDeviceOpen(
                    device, IOOptionBits(kIOHIDOptionsTypeNone)
                )
                guard openResult == kIOReturnSuccess else {
                    throw HardwareError.openFailed(path: path, result: openResult)
                }
                let advertisedLength = service.number("MaxInputReportSize")?.intValue ?? 64
                let bufferLength = max(64, advertisedLength)
                let channel = IMUChannel(
                    owner: self,
                    path: path,
                    device: device,
                    reportBufferLength: bufferLength
                )
                channels.append(channel)
                IOHIDDeviceRegisterInputReportCallback(
                    device,
                    channel.reportBuffer,
                    bufferLength,
                    imuInputReportCallback,
                    Unmanaged.passUnretained(channel).toOpaque()
                )
                IOHIDDeviceScheduleWithRunLoop(
                    device, runLoop, CFRunLoopMode.defaultMode.rawValue
                )
            }
        } catch {
            closeDevices(on: runLoop)
            throw error
        }
    }

    private func handleUnexpectedWorkerExit(on runLoop: CFRunLoop) {
        let shouldReport = lifecycleLock.withLock { running }
        guard shouldReport else { return }
        closeDevices(on: runLoop)
        restoreProperties()
        emit(.failed(path: nil, reason: "IMU RunLoop stopped unexpectedly"))
        lifecycleLock.withLock {
            running = false
            eventHandler = nil
            workerRunLoop = nil
            workerThread = nil
        }
    }

    private func closeDevices(on runLoop: CFRunLoop) {
        for channel in channels {
            IOHIDDeviceUnscheduleFromRunLoop(
                channel.device, runLoop, CFRunLoopMode.defaultMode.rawValue
            )
            IOHIDDeviceClose(
                channel.device, IOOptionBits(kIOHIDOptionsTypeNone)
            )
        }
        channels.removeAll()
    }

    private func restoreProperties() {
        for path in paths.reversed() {
            guard let service = registryServices[path],
                  let keys = changedProperties[path],
                  let snapshots = savedProperties[path],
                  let written = writtenProperties[path] else { continue }
            for key in keys.reversed() {
                guard let oldValue = snapshots[key],
                      let writtenValue = written[key] else { continue }
                if service.property(key, equals: oldValue) {
                    continue
                }
                guard service.property(key, equals: writtenValue) else {
                    emit(.warning(
                        path: path,
                        message: "not restoring \(key): value changed after acquisition"
                    ))
                    continue
                }
                let result = service.setProperty(key, value: oldValue)
                if result != KERN_SUCCESS {
                    emit(.warning(
                        path: path,
                        message: "failed to restore \(key): \(ioResult(result))"
                    ))
                }
            }
        }
        changedProperties.removeAll()
        writtenProperties.removeAll()
        savedProperties.removeAll()
    }

    private func performOnWorker(_ body: @escaping () throws -> Void) throws {
        let state: (CFRunLoop, Thread) = try lifecycleLock.withLock {
            guard running, let runLoop = workerRunLoop, let thread = workerThread else {
                throw HardwareError.invalidConfiguration("IMU source is not running")
            }
            return (runLoop, thread)
        }
        if Thread.current === state.1 {
            try body()
            return
        }

        let semaphore = DispatchSemaphore(value: 0)
        let result = ResultBox<Void>()
        CFRunLoopPerformBlock(state.0, CFRunLoopMode.defaultMode.rawValue) {
            result.result = Result { try body() }
            semaphore.signal()
        }
        CFRunLoopWakeUp(state.0)
        semaphore.wait()
        try result.result?.get()
    }

    private func emit(_ event: SensorSourceEvent) {
        let handler = lifecycleLock.withLock { eventHandler }
        handler?(event)
    }

    private func resetStatistics() {
        statisticsLock.withLock {
            reportCounts.removeAll()
            firstSampleTimes.removeAll()
            lastSampleTimes.removeAll()
            firstLengths.removeAll()
            firstHex.removeAll()
            oddLengthCounts.removeAll()
            callbackErrorCounts.removeAll()
            reportedCallbackFailures.removeAll()
            malformedMessage = nil
            _wakeRequired = false
            _wakePropertiesSet.removeAll()
            _reportIntervalUsed = nil
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
