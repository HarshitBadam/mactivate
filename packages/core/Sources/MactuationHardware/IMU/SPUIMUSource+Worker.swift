import CoreFoundation
import Foundation
import IOKit
import IOKit.hid
import MactuationCore

extension SPUIMUSource {
    func prepareWorker(on runLoop: CFRunLoop) throws {
        lifecycleLock.withLock { workerRunLoop = runLoop }
        do {
            for path in paths {
                do {
                    try prepareChannel(path: path, on: runLoop)
                } catch {
                    guard path == .spuGyroscope,
                          allowMissingGyroscope else {
                        throw error
                    }
                    disabledPaths.insert(path)
                    emit(.failed(
                        path: path,
                        reason: "optional gyroscope failed to start: \(error)"
                    ))
                }
            }
        } catch {
            closeDevices(on: runLoop)
            throw error
        }
    }

    private func prepareChannel(
        path: SensorPath,
        on runLoop: CFRunLoop
    ) throws {
        guard let service = deviceServices[path],
              let device = IOHIDDeviceCreate(
                kCFAllocatorDefault,
                service.entry
              ) else {
            throw HardwareError.deviceAbsent(path)
        }
        let openResult = IOHIDDeviceOpen(
            device,
            IOOptionBits(kIOHIDOptionsTypeNone)
        )
        guard openResult == kIOReturnSuccess else {
            throw HardwareError.openFailed(path: path, result: openResult)
        }
        let advertisedLength =
            service.number("MaxInputReportSize")?.intValue ?? 64
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
            device,
            runLoop,
            CFRunLoopMode.defaultMode.rawValue
        )
    }

    func handleUnexpectedWorkerExit(on runLoop: CFRunLoop) {
        let shouldReport = lifecycleLock.withLock {
            let wasRunning = running
            running = false
            return wasRunning
        }
        closeDevices(on: runLoop)
        restoreProperties()
        if shouldReport {
            emit(.failed(path: nil, reason: "IMU RunLoop stopped unexpectedly"))
        }
        clearWorkerState()
    }

    func cleanupStartupFailure(on runLoop: CFRunLoop) {
        closeDevices(on: runLoop)
        restoreProperties()
    }

    func clearWorkerState() {
        lifecycleLock.withLock {
            running = false
            eventHandler = nil
            workerRunLoop = nil
            workerThread = nil
            workerExitSemaphore = nil
        }
    }

    func closeDevices(on runLoop: CFRunLoop) {
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

    func performOnWorker(_ body: @escaping () throws -> Void) throws {
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
        guard semaphore.wait(
            timeout: .now() + SPUIMUSource.workerRequestTimeout
        ) == .success else {
            throw HardwareError.registry(
                "timed out waiting for the IMU worker request"
            )
        }
        guard let completed = result.result else {
            throw HardwareError.registry(
                "IMU worker did not report the request result"
            )
        }
        try completed.get()
    }

    func emit(_ event: SensorSourceEvent) {
        let handler = lifecycleLock.withLock { eventHandler }
        handler?(event)
    }
}
