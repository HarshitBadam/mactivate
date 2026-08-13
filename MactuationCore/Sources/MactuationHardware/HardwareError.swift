import Foundation
import IOKit
import MactuationCore

public enum HardwareError: Error, CustomStringConvertible, Equatable {
    case invalidConfiguration(String)
    case registry(String)
    case deviceAbsent(SensorPath)
    case openFailed(path: SensorPath, result: IOReturn)
    case propertySetFailed(path: SensorPath, key: String, result: IOReturn)
    case wakeFailed(String)

    public var description: String {
        switch self {
        case .invalidConfiguration(let reason), .registry(let reason):
            return reason
        case .deviceAbsent(let path):
            return "\(path.rawValue) HID service is absent"
        case .openFailed(let path, let result):
            return "IOHIDDeviceOpen(\(path.rawValue)) failed with \(ioResult(result))"
        case .propertySetFailed(let path, let key, let result):
            return "setting \(path.rawValue).\(key) failed with \(ioResult(result))"
        case .wakeFailed(let reason):
            return "SPU wake sequence failed: \(reason)"
        }
    }

    public var isPrivilegeFailure: Bool {
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

func ioResult(_ result: kern_return_t) -> String {
    "0x\(String(UInt32(bitPattern: result), radix: 16))"
}
