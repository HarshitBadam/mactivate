import Darwin
import Foundation
import MactuationCapture
import MactuationCore
import MactuationHardware

enum ProbeError: Error, CustomStringConvertible {
    case usage(String)
    case hardware(String)
    case capture(String)

    var description: String {
        switch self {
        case .usage(let message), .hardware(let message), .capture(let message):
            return message
        }
    }
}

struct Arguments {
    let values: [String]

    func has(_ flag: String) -> Bool {
        values.contains(flag)
    }

    func value(after flag: String) throws -> String? {
        guard let index = values.firstIndex(of: flag) else { return nil }
        guard values.indices.contains(index + 1), !values[index + 1].hasPrefix("--") else {
            throw ProbeError.usage("\(flag) requires a value")
        }
        return values[index + 1]
    }

    func double(after flag: String, default defaultValue: Double) throws -> Double {
        guard let raw = try value(after: flag) else { return defaultValue }
        guard let value = Double(raw), value.isFinite, value > 0 else {
            throw ProbeError.usage("\(flag) must be a positive number")
        }
        return value
    }

    func integer(after flag: String, default defaultValue: Int) throws -> Int {
        guard let raw = try value(after: flag) else { return defaultValue }
        guard let value = Int(raw), value > 0 else {
            throw ProbeError.usage("\(flag) must be a positive integer")
        }
        return value
    }
}

func collectCaptureEnvironment(requiredPrivileges: [String] = []) -> SessionManifest.Environment {
    var seen: Set<UInt64> = []
    let usages = (try? SPUHardwareInspector.inspect())?.services.compactMap {
        service -> SessionManifest.Environment.HIDUsage? in
        guard let page = service.usagePage, let usage = service.usage else { return nil }
        let key = (UInt64(page) << 32) | UInt64(usage)
        guard seen.insert(key).inserted else { return nil }
        return SessionManifest.Environment.HIDUsage(usagePage: page, usage: usage)
    } ?? []
    return EnvironmentProbe.collect(discoveredUsages: usages, requiredPrivileges: requiredPrivileges)
}

func jsonString<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    return String(decoding: try encoder.encode(value), as: UTF8.self)
}

func runLoop(until deadline: TimeInterval,
             stopWhen: () -> Bool = { false }) {
    while ProcessInfo.processInfo.systemUptime < deadline && !stopWhen() {
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
    }
}

func privilegeRerunError(_ error: HardwareError, command: String) -> ProbeError {
    .hardware(
        "\(error)\nRerun with: sudo .build/debug/mactuation-probe \(command) ..."
    )
}
