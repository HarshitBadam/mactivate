import CoreFoundation
import Foundation
import IOKit

final class SPURegistryService {
    let entry: io_registry_entry_t
    let className: String
    let entryID: UInt64
    let registryPath: String

    init(entry: io_registry_entry_t) {
        self.entry = entry
        IOObjectRetain(entry)

        if let copiedClass = IOObjectCopyClass(entry)?.takeRetainedValue() {
            className = copiedClass as String
        } else {
            className = "unknown"
        }

        var identifier: UInt64 = 0
        entryID = IORegistryEntryGetRegistryEntryID(entry, &identifier) == KERN_SUCCESS ? identifier : 0

        var path = [CChar](repeating: 0, count: 4096)
        if IORegistryEntryGetPath(entry, kIOServicePlane, &path) == KERN_SUCCESS {
            registryPath = String(cString: path)
        } else {
            registryPath = "unknown"
        }
    }

    deinit {
        IOObjectRelease(entry)
    }

    func property(_ key: String) -> AnyObject? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
    }

    func number(_ key: String) -> NSNumber? {
        property(key) as? NSNumber
    }

    func string(_ key: String) -> String? {
        property(key) as? String
    }

    @discardableResult
    func setProperty(_ key: String, value: AnyObject) -> kern_return_t {
        IORegistryEntrySetCFProperty(entry, key as CFString, value)
    }

    var usagePage: UInt32? { number("PrimaryUsagePage").map { $0.uint32Value } }
    var usage: UInt32? { number("PrimaryUsage").map { $0.uint32Value } }

    func humanDescription() -> String {
        [
            "\(className) id=0x\(String(entryID, radix: 16))",
            "  usage=\(formattedUsage())",
            "  ReportInterval=\(formattedProperty("ReportInterval"))",
            "  sensor_rates=\(formattedProperty("sensor_rates"))",
            "  MaxInputReportSize=\(formattedProperty("MaxInputReportSize"))",
            "  path=\(registryPath)"
        ].joined(separator: "\n")
    }

    private func formattedUsage() -> String {
        guard let usagePage, let usage else { return "unknown" }
        return "0x\(String(usagePage, radix: 16))/0x\(String(usage, radix: 16)) (\(usagePage)/\(usage))"
    }

    private func formattedProperty(_ key: String) -> String {
        guard let value = property(key) else { return "n/a" }
        if let data = value as? Data {
            return data.map { String(format: "%02x", $0) }.joined()
        }
        return String(describing: value)
    }
}

enum SPURegistry {
    static func discover() throws -> [SPURegistryService] {
        var services: [SPURegistryService] = []
        for className in ["AppleSPUHIDDriver", "AppleSPUHIDDevice"] {
            guard let matching = IOServiceMatching(className) else {
                throw ProbeError.hardware("could not create IOKit match for \(className)")
            }
            var iterator: io_iterator_t = 0
            let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
            guard result == KERN_SUCCESS else {
                throw ProbeError.hardware("IOServiceGetMatchingServices(\(className)) failed: \(ioResult(result))")
            }
            defer { IOObjectRelease(iterator) }
            while true {
                let entry = IOIteratorNext(iterator)
                guard entry != 0 else { break }
                services.append(SPURegistryService(entry: entry))
                IOObjectRelease(entry)
            }
        }
        return services
    }

    static func driver(usagePage: UInt32, usage: UInt32) throws -> SPURegistryService? {
        try discover().first { $0.usagePage == usagePage && $0.usage == usage }
    }

    static func ioResult(_ result: kern_return_t) -> String {
        "0x\(String(UInt32(bitPattern: result), radix: 16))"
    }
}

func ioResult(_ result: kern_return_t) -> String {
    SPURegistry.ioResult(result)
}
