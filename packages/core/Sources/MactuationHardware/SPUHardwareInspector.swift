import Foundation
import IOKit
import IOKit.hid
import MactuationCore

public struct SPUServiceDescription: Equatable, Sendable {
    public let className: String
    public let entryID: UInt64
    public let registryPath: String
    public let usagePage: UInt32?
    public let usage: UInt32?
    public let reportInterval: String?
    public let sensorRates: String?
    public let maxInputReportSize: String?

    public func humanDescription() -> String {
        let usageDescription: String
        if let usagePage, let usage {
            usageDescription =
                "0x\(String(usagePage, radix: 16))/0x\(String(usage, radix: 16)) " +
                "(\(usagePage)/\(usage))"
        } else {
            usageDescription = "unknown"
        }
        return [
            "\(className) id=0x\(String(entryID, radix: 16))",
            "  usage=\(usageDescription)",
            "  ReportInterval=\(reportInterval ?? "n/a")",
            "  sensor_rates=\(sensorRates ?? "n/a")",
            "  MaxInputReportSize=\(maxInputReportSize ?? "n/a")",
            "  path=\(registryPath)"
        ].joined(separator: "\n")
    }
}

public struct SPUHardwareSnapshot: Equatable, Sendable {
    public let services: [SPUServiceDescription]
    public let states: [SensorPath: CapabilityState]
    public let currentAmbientLux: Double?

    public func state(of path: SensorPath) -> CapabilityState {
        states[path] ?? .unknown
    }
}

private extension SPURegistryService {
    func descriptionValue() -> SPUServiceDescription {
        SPUServiceDescription(
            className: className,
            entryID: entryID,
            registryPath: registryPath,
            usagePage: usagePage,
            usage: usage,
            reportInterval: formattedProperty("ReportInterval"),
            sensorRates: formattedProperty("sensor_rates"),
            maxInputReportSize: formattedProperty("MaxInputReportSize")
        )
    }

    func formattedProperty(_ key: String) -> String? {
        guard let value = property(key) else { return nil }
        if let data = value as? Data {
            return data.map { String(format: "%02x", $0) }.joined()
        }
        return String(describing: value)
    }
}

public enum SPUHardwareInspector {
    public static func inspect() throws -> SPUHardwareSnapshot {
        let services = try SPURegistry.discover()
        let ambient = services.first {
            $0.className != "AppleSPUHIDDevice" &&
                $0.usagePage == 0xFF00 && $0.usage == 4
        }
        let lux = ambient?.number("CurrentLux")?.doubleValue
        var states: [SensorPath: CapabilityState] = [:]
        states[.spuAccelerometer] = HIDOpenProbe.probe(
            services: services, usagePage: 0xFF00, usage: 3
        )
        states[.spuGyroscope] = HIDOpenProbe.probe(
            services: services, usagePage: 0xFF00, usage: 9
        )
        if let lux {
            states[.spuAmbientLight] = .available(
                detail: "unprivileged AppleSPUVD6286 CurrentLux registry poll succeeded (lux=\(lux))"
            )
        } else if ambient != nil {
            states[.spuAmbientLight] = .unavailable(
                reason: "SPU ALS usage 0xFF00/4 present, but CurrentLux was unreadable"
            )
        } else {
            states[.spuAmbientLight] = .unavailable(
                reason: "Apple SPU HID usage 0xFF00/4 absent"
            )
        }
        return SPUHardwareSnapshot(
            services: services.map { $0.descriptionValue() },
            states: states,
            currentAmbientLux: lux
        )
    }
}

private enum HIDOpenProbe {
    static func probe(services: [SPURegistryService], usagePage: UInt32,
                      usage: UInt32) -> CapabilityState {
        guard let service = services.first(where: {
            $0.className == "AppleSPUHIDDevice" &&
                $0.usagePage == usagePage && $0.usage == usage
        }) else {
            return .unavailable(reason: String(
                format: "Apple SPU HID usage 0x%X/%d absent", usagePage, usage
            ))
        }
        guard let device = IOHIDDeviceCreate(kCFAllocatorDefault, service.entry) else {
            return .unavailable(
                reason: "IOHIDDeviceCreate failed for \(service.registryPath)"
            )
        }
        let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        if result == kIOReturnSuccess {
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
            let euid = geteuid()
            return .available(
                detail: "HID open succeeded (euid \(euid)\(euid == 0 ? "" : ", unprivileged"))"
            )
        }
        if result == kIOReturnNotPrivileged || result == kIOReturnNotPermitted {
            return .needsPrivilege(
                privilege: "root (open failed with \(ioResult(result)))"
            )
        }
        return .unavailable(reason: "HID open failed with \(ioResult(result))")
    }
}
