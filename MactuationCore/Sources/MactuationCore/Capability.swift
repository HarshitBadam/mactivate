import Foundation

/// Capability state of one sensor path on the current machine.
///
/// Every real path starts `.unknown`; only evidence observed on the running
/// machine (or ingested probe results) may promote it. Unsupported hardware
/// must degrade to `.unavailable` with a reason, never crash.
public enum CapabilityState: Codable, Equatable, Sendable {
    case unknown
    case available(detail: String)
    case unavailable(reason: String)
    case needsPrivilege(privilege: String)
    /// Present and readable, but behind an explicit user opt-in
    /// (camera/microphone privacy rule).
    case needsOptIn

    public var allowsAcquisition: Bool {
        if case .available = self { return true }
        return false
    }
}

public struct CapabilityReport: Codable, Equatable, Sendable {
    public var states: [SensorPath: CapabilityState]
    public var generatedAt: Date

    public init(states: [SensorPath: CapabilityState] = [:], generatedAt: Date = Date()) {
        self.states = states
        self.generatedAt = generatedAt
    }

    public static func allUnknown() -> CapabilityReport {
        CapabilityReport(states: Dictionary(uniqueKeysWithValues: SensorPath.allCases.map { ($0, .unknown) }))
    }

    public func state(of path: SensorPath) -> CapabilityState {
        states[path] ?? .unknown
    }
}
