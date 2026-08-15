import CoreFoundation
import Foundation
import IOKit
import IOKit.hid
import MactuationCore

public final class SPUIMUSource: SensorSource {
    public let paths: [SensorPath]

    static let startupTimeout: DispatchTimeInterval = .seconds(10)
    static let workerRequestTimeout: DispatchTimeInterval = .seconds(2)

    private let operationLock = NSLock()
    let lifecycleLock = NSLock()
    let statisticsLock = NSLock()
    private let startupReportInterval: Int?
    let allowMissingGyroscope: Bool
    let registryServices: [SensorPath: SPURegistryService]
    let deviceServices: [SensorPath: SPURegistryService]
    var channels: [IMUChannel] = []
    var disabledPaths: Set<SensorPath> = []
    var eventHandler: ((SensorSourceEvent) -> Void)?
    var workerThread: Thread?
    var workerRunLoop: CFRunLoop?
    var workerExitSemaphore: DispatchSemaphore?
    var running = false
    var startUptime: TimeInterval = 0

    var reportCounts: [SensorPath: Int] = [:]
    var firstSampleTimes: [SensorPath: TimeInterval] = [:]
    var lastSampleTimes: [SensorPath: TimeInterval] = [:]
    var firstLengths: [SensorPath: Int] = [:]
    var firstHex: [SensorPath: String] = [:]
    var oddLengthCounts: [SensorPath: Int] = [:]
    var callbackErrorCounts: [SensorPath: Int] = [:]
    var reportedCallbackFailures: Set<SensorPath> = []
    var malformedMessage: String?
    var savedProperties: [SensorPath: [String: AnyObject]] = [:]
    var writtenProperties: [SensorPath: [String: AnyObject]] = [:]
    var changedProperties: [SensorPath: [String]] = [:]
    var _wakeRequired = false
    var _wakePropertiesSet: [String] = []
    var _reportIntervalUsed: Int?

    public init(
        includeGyroscope: Bool,
        allowMissingGyroscope: Bool = false,
        startupReportInterval: Int? = nil
    ) throws {
        if let startupReportInterval, startupReportInterval <= 0 {
            throw HardwareError.invalidConfiguration(
                "startup report interval must be a positive number of microseconds"
            )
        }
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
                if path == .spuGyroscope && allowMissingGyroscope {
                    continue
                }
                throw HardwareError.deviceAbsent(path)
            }
            drivers[path] = driver
            devices[path] = device
        }
        self.startupReportInterval = startupReportInterval
        self.allowMissingGyroscope = allowMissingGyroscope
        paths = requested.filter { drivers[$0] != nil && devices[$0] != nil }
        registryServices = drivers
        deviceServices = devices
    }

    deinit {
        stop()
    }

    public func start(handler: @escaping (SensorSourceEvent) -> Void) throws {
        operationLock.lock()
        defer { operationLock.unlock() }

        let handshake = StartHandshake()
        let workerExit = DispatchSemaphore(value: 0)
        let thread: Thread = try lifecycleLock.withLock {
            guard !running, workerThread == nil else {
                throw SensorSourceError.alreadyStarted
            }
            running = true
            disabledPaths.removeAll(keepingCapacity: true)
            eventHandler = handler
            startUptime = ProcessInfo.processInfo.systemUptime
            resetStatistics()

            let thread = Thread { [weak self, handshake, workerExit] in
                defer { workerExit.signal() }
                let runLoop = CFRunLoopGetCurrent()
                do {
                    guard let runLoop else {
                        throw HardwareError.registry("could not create IMU worker RunLoop")
                    }
                    guard let source = self else {
                        throw HardwareError.registry("IMU source was released during startup")
                    }
                    try source.prepareWorker(on: runLoop)
                    if let interval = source.startupReportInterval {
                        try source.applyWakeSequenceOnWorker(
                            reportInterval: interval
                        )
                    }
                    guard handshake.complete(.success(())) else {
                        source.cleanupStartupFailure(on: runLoop)
                        source.clearWorkerState()
                        return
                    }
                } catch {
                    if let runLoop, let source = self {
                        source.cleanupStartupFailure(on: runLoop)
                        source.clearWorkerState()
                    }
                    _ = handshake.complete(.failure(error))
                }

                guard case .success? = handshake.result else { return }
                CFRunLoopRun()
                if let runLoop = CFRunLoopGetCurrent() {
                    self?.handleUnexpectedWorkerExit(on: runLoop)
                }
            }
            thread.name = "com.mactivate.spu-imu-runloop"
            thread.qualityOfService = .utility
            workerThread = thread
            workerExitSemaphore = workerExit
            return thread
        }

        thread.start()
        guard handshake.semaphore.wait(
            timeout: .now() + Self.startupTimeout
        ) == .success else {
            handshake.cancel()
            lifecycleLock.withLock {
                running = false
                eventHandler = nil
            }
            throw HardwareError.registry(
                "timed out waiting for the IMU worker to start"
            )
        }
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
                workerExitSemaphore = nil
            }
            throw error
        }
    }

    public func stop() {
        operationLock.lock()
        defer { operationLock.unlock() }

        let state: (
            CFRunLoop,
            Thread,
            DispatchSemaphore,
            (SensorSourceEvent) -> Void
        )? =
            lifecycleLock.withLock {
                guard running, let runLoop = workerRunLoop,
                      let thread = workerThread,
                      let workerExitSemaphore,
                      let handler = eventHandler else {
                    return nil
                }
                running = false
                return (runLoop, thread, workerExitSemaphore, handler)
            }
        guard let (runLoop, thread, workerExit, handler) = state else { return }

        let cleanup = {
            self.closeDevices(on: runLoop)
            self.restoreProperties()
            handler(.completed)
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
        guard semaphore.wait(
            timeout: .now() + Self.workerRequestTimeout
        ) == .success else {
            handler(.warning(
                path: nil,
                message: "timed out waiting for the IMU worker to stop"
            ))
            CFRunLoopStop(runLoop)
            CFRunLoopWakeUp(runLoop)
            return
        }
        if workerExit.wait(
            timeout: .now() + Self.workerRequestTimeout
        ) != .success {
            handler(.warning(
                path: nil,
                message: "IMU worker did not exit promptly after shutdown"
            ))
        }
    }
}
