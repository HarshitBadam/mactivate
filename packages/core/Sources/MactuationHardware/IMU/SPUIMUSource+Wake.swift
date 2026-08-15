import CoreFoundation
import Foundation
import IOKit
import IOKit.hid
import MactuationCore

/// The SPU HID registry only reports IMU samples after specific properties
/// are written (reporting/power state, report interval); this "wake
/// sequence" applies those, remembers the pre-existing values so `stop()`
/// can restore exactly what was there before, and tolerates the optional
/// gyroscope failing independently of the required accelerometer.
extension SPUIMUSource {
    public func applyWakeSequenceIfNeeded(reportInterval: Int = 10_000) throws {
        guard reportInterval > 0 else {
            throw HardwareError.invalidConfiguration(
                "report interval must be a positive number of microseconds"
            )
        }
        try performOnWorker {
            try self.applyWakeSequenceOnWorker(reportInterval: reportInterval)
        }
    }

    func applyWakeSequenceOnWorker(reportInterval: Int) throws {
        let pathsNeedingWake = statisticsLock.withLock {
            paths.filter {
                !disabledPaths.contains($0) &&
                    reportCounts[$0, default: 0] == 0
            }
        }
        guard !pathsNeedingWake.isEmpty else { return }
        statisticsLock.withLock { _wakeRequired = true }

        let desired: [(String, AnyObject)] = [
            ("SensorPropertyReportingState", NSNumber(value: Int32(1))),
            ("SensorPropertyPowerState", NSNumber(value: Int32(1))),
            ("ReportInterval", NSNumber(value: Int32(reportInterval)))
        ]

        for path in pathsNeedingWake {
            do {
                try applyWakeSequence(
                    to: path,
                    desired: desired
                )
            } catch {
                restoreProperties(for: path)
                guard path == .spuGyroscope,
                      allowMissingGyroscope else {
                    restoreProperties()
                    throw error
                }
                disabledPaths.insert(path)
                if let runLoop = CFRunLoopGetCurrent() {
                    closeChannel(path: path, on: runLoop)
                }
                emit(.failed(
                    path: path,
                    reason: "optional gyroscope wake failed: \(error)"
                ))
            }
        }
        statisticsLock.withLock {
            _reportIntervalUsed = reportInterval
        }
    }

    private func applyWakeSequence(
        to path: SensorPath,
        desired: [(String, AnyObject)]
    ) throws {
        guard let service = registryServices[path] else { return }
        var snapshots: [String: AnyObject] = [:]
        for (key, _) in desired {
            if let value = service.property(key) {
                snapshots[key] = value
            } else if key == "ReportInterval" {
                throw HardwareError.wakeFailed(
                    "\(path.rawValue) has no readable pre-existing ReportInterval"
                )
            } else {
                snapshots[key] = NSNumber(value: Int32(0))
            }
        }
        savedProperties[path] = snapshots

        for (key, value) in desired {
            let result = service.setProperty(key, value: value)
            guard result == KERN_SUCCESS else {
                throw HardwareError.propertySetFailed(
                    path: path,
                    key: key,
                    result: result
                )
            }
            changedProperties[path, default: []].append(key)
            writtenProperties[path, default: [:]][key] = value
            statisticsLock.withLock {
                if !_wakePropertiesSet.contains(key) {
                    _wakePropertiesSet.append(key)
                }
            }
        }
    }

    /// Closes and forgets one channel outside the normal shutdown path, used
    /// only when the optional gyroscope's wake sequence fails and the
    /// accelerometer must keep running without it.
    private func closeChannel(path: SensorPath, on runLoop: CFRunLoop) {
        guard let index = channels.firstIndex(where: {
            $0.path == path
        }) else {
            return
        }
        let channel = channels.remove(at: index)
        IOHIDDeviceUnscheduleFromRunLoop(
            channel.device,
            runLoop,
            CFRunLoopMode.defaultMode.rawValue
        )
        IOHIDDeviceClose(
            channel.device,
            IOOptionBits(kIOHIDOptionsTypeNone)
        )
    }

    func restoreProperties() {
        for path in paths.reversed() {
            restoreProperties(for: path)
        }
        changedProperties.removeAll()
        writtenProperties.removeAll()
        savedProperties.removeAll()
    }

    private func restoreProperties(for path: SensorPath) {
        defer {
            changedProperties[path] = nil
            writtenProperties[path] = nil
            savedProperties[path] = nil
        }
        guard let service = registryServices[path],
              let keys = changedProperties[path],
              let snapshots = savedProperties[path],
              let written = writtenProperties[path] else {
            return
        }
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
}
