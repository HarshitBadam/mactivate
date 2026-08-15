import Foundation
import MactuationCore
import MactuationHardware

func capabilityDescription(_ state: CapabilityState) -> String {
    switch state {
    case .unknown:
        return "unknown"
    case .available(let detail):
        return "available — \(detail)"
    case .unavailable(let reason):
        return "unavailable — \(reason)"
    case .needsPrivilege(let privilege):
        return "needs privilege — \(privilege)"
    case .needsOptIn:
        return "needs explicit opt-in"
    }
}

func makeCapabilityReport(snapshot: SPUHardwareSnapshot,
                          displayServices: DisplayServicesStatus) -> CapabilityReport {
    var states: [SensorPath: CapabilityState] = [:]
    states[.spuAccelerometer] = snapshot.state(of: .spuAccelerometer)
    states[.spuGyroscope] = snapshot.state(of: .spuGyroscope)
    states[.spuAmbientLight] = snapshot.state(of: .spuAmbientLight)
    states[.displayServicesAmbientLight] = displayServices.frameworkPresent
        ? .unknown
        : .unavailable(reason: "DisplayServices.framework absent")
    states[.microphone] = .needsOptIn
    states[.camera] = .needsOptIn
    return CapabilityReport(states: states)
}

func runDiscover(_ arguments: Arguments) throws {
    let snapshot = try SPUHardwareInspector.inspect()
    let displayServices = DisplayServicesProbe.inspect()
    let report = makeCapabilityReport(snapshot: snapshot, displayServices: displayServices)
    if arguments.has("--json") {
        print(try jsonString(report))
        return
    }

    if snapshot.services.isEmpty {
        print("No AppleSPUHIDDriver or AppleSPUHIDDevice services found.")
    } else {
        print("IOKit SPU services (\(snapshot.services.count)):")
        for service in snapshot.services {
            print(service.humanDescription())
        }
    }

    let coreMotion = CoreMotionProbe.accelerometerAvailable()
    print("CoreMotion accelerometer available: \(coreMotion.map(String.init) ?? "unknown (CMMotionManager absent)")")
    print("DisplayServices framework present: \(displayServices.frameworkPresent)")
    print("DisplayServices framework loadable: \(displayServices.frameworkLoadable)")
    print("DisplayServices AggregatedLux: unknown — \(displayServices.detail)")
    print("Capabilities:")
    for path in SensorPath.allCases {
        print("  \(path.rawValue): \(capabilityDescription(report.state(of: path)))")
    }
}
