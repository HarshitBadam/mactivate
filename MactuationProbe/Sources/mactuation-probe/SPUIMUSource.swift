import CoreFoundation
import Foundation
import IOKit
import IOKit.hid
import MactuationCore

enum SPUIMUError: Error, CustomStringConvertible {
    case deviceAbsent(SensorPath)
    case openFailed(path: SensorPath, result: IOReturn)
    case propertySetFailed(path: SensorPath, key: String, result: IOReturn)
    case wakeFailed(String)

    var description: String {
        switch self {
        case .deviceAbsent(let path):
            return "\(path.rawValue) HID service is absent"
        case .openFailed(let path, let result):
            return "IOHIDDeviceOpen(\(path.rawValue)) failed with \(ioResult(result))"
        case .propertySetFailed(let path, let key, let result):
            return "IORegistryEntrySetCFProperty(\(path.rawValue).\(key)) failed with \(ioResult(result))"
        case .wakeFailed(let reason):
            return "SPU wake sequence failed: \(reason)"
        }
    }

    var isPrivilegeFailure: Bool {
        let result: IOReturn
        switch self {
        case .openFailed(_, let value), .propertySetFailed(_, _, let value):
            result = value
        default:
            return false
        }
        return result == kIOReturnNotPrivileged || result == kIOReturnNotPermitted ||
            result == kIOReturnExclusiveAccess
    }
}

private final class IMUChannel {
    weak var owner: SPUIMUSource?
    let path: SensorPath
    let service: SPURegistryService
    let device: IOHIDDevice
    let reportBuffer: UnsafeMutablePointer<UInt8>
    let reportBufferLength: Int

    init(owner: SPUIMUSource, path: SensorPath, service: SPURegistryService,
         device: IOHIDDevice, reportBufferLength: Int) {
        self.owner = owner
        self.path = path
        self.service = service
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

final class SPUIMUSource: SensorSource {
    let paths: [SensorPath]

    private let lock = NSLock()
    private let registryServices: [SensorPath: SPURegistryService]
    private let deviceServices: [SensorPath: SPURegistryService]
    private var channels: [IMUChannel] = []
    private var handler: ((SensorSample) -> Void)?
    private var startUptime: TimeInterval = 0
    private var running = false
    private var reportCounts: [SensorPath: Int] = [:]
    private var firstSampleTimes: [SensorPath: TimeInterval] = [:]
    private var lastSampleTimes: [SensorPath: TimeInterval] = [:]
    private var firstLengths: [SensorPath: Int] = [:]
    private var firstHex: [SensorPath: String] = [:]
    private var oddLengthCounts: [SensorPath: Int] = [:]
    private var callbackErrorCounts: [SensorPath: Int] = [:]
    private var malformedMessage: String?
    private var savedProperties: [SensorPath: [String: AnyObject]] = [:]
    private var changedProperties: [SensorPath: [String]] = [:]
    private(set) var wakeRequired = false
    private(set) var wakePropertiesSet: [String] = []
    private(set) var reportIntervalUsed: Int?

    init(includeGyroscope: Bool) throws {
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
                throw SPUIMUError.deviceAbsent(path)
            }
            drivers[path] = driver
            devices[path] = device
        }
        paths = requested
        registryServices = drivers
        deviceServices = devices
    }

    func start(handler: @escaping (SensorSample) -> Void) throws {
        guard !running else { throw SensorSourceError.alreadyStarted }
        self.handler = handler
        startUptime = ProcessInfo.processInfo.systemUptime

        do {
            for path in paths {
                guard let service = deviceServices[path],
                      let device = IOHIDDeviceCreate(kCFAllocatorDefault, service.entry) else {
                    throw SPUIMUError.deviceAbsent(path)
                }
                let openResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
                guard openResult == kIOReturnSuccess else {
                    throw SPUIMUError.openFailed(path: path, result: openResult)
                }

                let advertisedLength = service.number("MaxInputReportSize")?.intValue ?? 64
                let bufferLength = max(64, advertisedLength)
                let channel = IMUChannel(owner: self, path: path, service: service,
                                         device: device, reportBufferLength: bufferLength)
                channels.append(channel)
                IOHIDDeviceRegisterInputReportCallback(
                    device,
                    channel.reportBuffer,
                    bufferLength,
                    imuInputReportCallback,
                    Unmanaged.passUnretained(channel).toOpaque()
                )
                IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            }
            running = true
        } catch {
            closeDevices()
            self.handler = nil
            throw error
        }
    }

    func applyWakeSequenceIfNeeded(reportInterval: Int = 10_000) throws {
        guard totalReportCount == 0 else { return }
        wakeRequired = true

        let desired: [(String, AnyObject)] = [
            ("SensorPropertyReportingState", NSNumber(value: Int32(1))),
            ("SensorPropertyPowerState", NSNumber(value: Int32(1))),
            ("ReportInterval", NSNumber(value: Int32(reportInterval)))
        ]

        for path in paths {
            guard let service = registryServices[path] else { continue }
            var snapshots: [String: AnyObject] = [:]
            for (key, _) in desired {
                if let value = service.property(key) {
                    snapshots[key] = value
                } else if key == "ReportInterval" {
                    restoreProperties()
                    throw SPUIMUError.wakeFailed(
                        "\(path.rawValue) has no readable pre-existing ReportInterval"
                    )
                } else {
                    // These command-like state properties are absent while the
                    // sensor sleeps. Restore the inactive value explicitly.
                    snapshots[key] = NSNumber(value: Int32(0))
                }
            }
            savedProperties[path] = snapshots

            for (key, value) in desired {
                let result = service.setProperty(key, value: value)
                guard result == KERN_SUCCESS else {
                    restoreProperties()
                    throw SPUIMUError.propertySetFailed(path: path, key: key, result: result)
                }
                changedProperties[path, default: []].append(key)
                if !wakePropertiesSet.contains(key) { wakePropertiesSet.append(key) }
            }
        }
        reportIntervalUsed = reportInterval
    }

    func stop() {
        guard running || !channels.isEmpty || !changedProperties.isEmpty else { return }
        running = false
        closeDevices()
        restoreProperties()
        handler = nil
    }

    var totalReportCount: Int {
        lock.withLock { reportCounts.values.reduce(0, +) }
    }

    func reportCount(for path: SensorPath) -> Int {
        lock.withLock { reportCounts[path, default: 0] }
    }

    func effectiveRate(for path: SensorPath, elapsed: TimeInterval) -> Double {
        lock.withLock {
            let count = reportCounts[path, default: 0]
            if count > 1, let first = firstSampleTimes[path], let last = lastSampleTimes[path],
               last > first {
                return Double(count - 1) / (last - first)
            }
            guard elapsed > 0 else { return 0 }
            return Double(count) / elapsed
        }
    }

    var malformedReport: String? {
        lock.withLock { malformedMessage }
    }

    func firstReportLength(for path: SensorPath) -> Int? {
        lock.withLock { firstLengths[path] }
    }

    func anomalies(for path: SensorPath) -> [String] {
        lock.withLock {
            var values: [String] = []
            let odd = oddLengthCounts[path, default: 0]
            let errors = callbackErrorCounts[path, default: 0]
            if odd > 0 { values.append("\(odd) reports differed from the first report length") }
            if errors > 0 { values.append("\(errors) callbacks returned non-success IOReturn") }
            if reportCounts[path, default: 0] == 0 { values.append("no input reports received") }
            return values
        }
    }

    fileprivate func receive(channel: IMUChannel, result: IOReturn,
                             report: UnsafeMutablePointer<UInt8>, length: Int) {
        let path = channel.path
        if result != kIOReturnSuccess {
            lock.withLock { callbackErrorCounts[path, default: 0] += 1 }
            return
        }

        var shouldLogFirst = false
        lock.withLock {
            if firstLengths[path] == nil {
                firstLengths[path] = length
                let bytes = UnsafeBufferPointer(start: report, count: max(0, length))
                firstHex[path] = bytes.map { String(format: "%02x", $0) }.joined()
                shouldLogFirst = true
                if length < 18 {
                    malformedMessage =
                        "\(path.rawValue) first report was \(length) bytes (<18); hex=\(firstHex[path] ?? "")"
                }
            } else if firstLengths[path] != length {
                oddLengthCounts[path, default: 0] += 1
            }
        }

        if shouldLogFirst {
            print("First \(path.rawValue) report length: \(length) bytes")
            if length < 18 {
                print("First report hex: \(lock.withLock { firstHex[path] ?? "" })")
            }
        }
        guard length >= 18 else { return }

        let x = decodeInt32(report, at: 6)
        let y = decodeInt32(report, at: 10)
        let z = decodeInt32(report, at: 14)
        let timestamp = ProcessInfo.processInfo.systemUptime - startUptime
        lock.withLock {
            reportCounts[path, default: 0] += 1
            if firstSampleTimes[path] == nil { firstSampleTimes[path] = timestamp }
            lastSampleTimes[path] = timestamp
        }
        handler?(.imu(path: path, sample: IMUSample(
            timestamp: timestamp,
            x: Double(x) / 65_536.0,
            y: Double(y) / 65_536.0,
            z: Double(z) / 65_536.0
        )))
    }

    private func closeDevices() {
        for channel in channels {
            IOHIDDeviceUnscheduleFromRunLoop(
                channel.device,
                CFRunLoopGetCurrent(),
                CFRunLoopMode.defaultMode.rawValue
            )
            IOHIDDeviceClose(channel.device, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        channels.removeAll()
    }

    private func restoreProperties() {
        for path in paths.reversed() {
            guard let service = registryServices[path],
                  let keys = changedProperties[path],
                  let snapshots = savedProperties[path] else { continue }
            for key in keys.reversed() {
                guard let oldValue = snapshots[key] else { continue }
                let result = service.setProperty(key, value: oldValue)
                if result != KERN_SUCCESS {
                    FileHandle.standardError.write(Data(
                        "warning: failed to restore \(path.rawValue).\(key): \(ioResult(result))\n".utf8
                    ))
                }
            }
        }
        changedProperties.removeAll()
        savedProperties.removeAll()
    }

    private func decodeInt32(_ bytes: UnsafeMutablePointer<UInt8>, at offset: Int) -> Int32 {
        let value = UInt32(bytes[offset]) |
            (UInt32(bytes[offset + 1]) << 8) |
            (UInt32(bytes[offset + 2]) << 16) |
            (UInt32(bytes[offset + 3]) << 24)
        return Int32(bitPattern: value)
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}

enum HIDOpenProbe {
    /// Empirically determines the privilege state of a HID path by attempting
    /// a real open (immediately closed, no reports requested, no properties
    /// touched). Discovery must measure, not assume — prior art claimed the
    /// SPU IMU needs root, which this machine refuted.
    static func probe(services: [SPURegistryService], usagePage: UInt32,
                      usage: UInt32) -> CapabilityState {
        guard let service = services.first(where: {
            $0.className == "AppleSPUHIDDevice" && $0.usagePage == usagePage && $0.usage == usage
        }) else {
            return .unavailable(reason: String(
                format: "Apple SPU HID usage 0x%X/%d absent", usagePage, usage))
        }
        guard let device = IOHIDDeviceCreate(kCFAllocatorDefault, service.entry) else {
            return .unavailable(reason: "IOHIDDeviceCreate failed for \(service.registryPath)")
        }
        let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        if result == kIOReturnSuccess {
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
            let euid = geteuid()
            return .available(detail: "HID open succeeded (euid \(euid)\(euid == 0 ? "" : ", unprivileged"))")
        }
        if result == kIOReturnNotPrivileged || result == kIOReturnNotPermitted {
            return .needsPrivilege(privilege: "root (open failed with \(ioResult(result)))")
        }
        return .unavailable(reason: "HID open failed with \(ioResult(result))")
    }
}
