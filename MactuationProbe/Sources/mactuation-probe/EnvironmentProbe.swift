import AppKit
import Darwin
import Foundation
import MactuationCore

enum EnvironmentProbe {
    static func collect(discoveredUsages: [SessionManifest.Environment.HIDUsage] = [],
                        requiredPrivileges: [String] = []) -> SessionManifest.Environment {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return SessionManifest.Environment(
            modelIdentifier: sysctlString("hw.model") ?? "unknown",
            chip: sysctlString("machdep.cpu.brand_string") ?? "unknown",
            osVersion: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            osBuild: sysctlString("kern.osversion") ?? "unknown",
            notchPresent: NSScreen.main.map { $0.safeAreaInsets.top > 0 },
            requiredPrivileges: requiredPrivileges,
            discoveredHIDUsages: discoveredUsages,
            compatibility: .unknown
        )
    }

    static func humanDescription(_ environment: SessionManifest.Environment) -> String {
        let notch: String
        switch environment.notchPresent {
        case true?: notch = "yes"
        case false?: notch = "no"
        case nil: notch = "unknown (no main screen)"
        }
        return """
        Model: \(environment.modelIdentifier)
        Chip: \(environment.chip)
        macOS: \(environment.osVersion)
        Build: \(environment.osBuild)
        Notch present: \(notch)
        """
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else {
            return nil
        }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &bytes, &size, nil, 0) == 0 else {
            return nil
        }
        return String(cString: bytes)
    }
}
