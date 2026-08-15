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

    @discardableResult
    func setProperty(_ key: String, value: AnyObject) -> kern_return_t {
        IORegistryEntrySetCFProperty(entry, key as CFString, value)
    }

    func property(_ key: String, equals expected: AnyObject) -> Bool {
        guard let current = property(key) else { return false }
        return CFEqual(current, expected)
    }

    var usagePage: UInt32? { number("PrimaryUsagePage").map(\.uint32Value) }
    var usage: UInt32? { number("PrimaryUsage").map(\.uint32Value) }
}

enum SPURegistry {
    static func discover() throws -> [SPURegistryService] {
        var services: [SPURegistryService] = []
        for className in ["AppleSPUHIDDriver", "AppleSPUHIDDevice"] {
            guard let matching = IOServiceMatching(className) else {
                throw HardwareError.registry("could not create IOKit match for \(className)")
            }
            var iterator: io_iterator_t = 0
            let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
            guard result == KERN_SUCCESS else {
                throw HardwareError.registry(
                    "IOServiceGetMatchingServices(\(className)) failed with \(ioResult(result))"
                )
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
        try discover().first {
            $0.className != "AppleSPUHIDDevice" &&
                $0.usagePage == usagePage && $0.usage == usage
        }
    }
}
