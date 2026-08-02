import Foundation

/// A tap binding: one region, one tap count, one action. Three bindings per
/// region, no more, because the tap vocabulary is closed.
public struct TapBinding: Identifiable, Equatable, Codable, Sendable {
    public var region: TapRegionID
    public var count: TapCount
    public var action: ActionSpec?
    /// Bindings can be muted without losing their action, which is what the
    /// "off" switch in the binding row does and what makes muting undoable.
    public var isEnabled: Bool

    public var id: String { "\(region.rawValue)#\(count.rawValue)" }

    public init(region: TapRegionID, count: TapCount, action: ActionSpec? = nil, isEnabled: Bool = true) {
        self.region = region
        self.count = count
        self.action = action
        self.isEnabled = isEnabled
    }

    public var isBound: Bool { action != nil }
}

/// How the panel may be opened. Hand-near is the primary trigger; the others
/// exist so the product still works when the hand-near hypothesis fails on a
/// given machine.
public struct TriggerSettings: Equatable, Codable, Sendable {
    public var handNearEnabled: Bool
    /// Sensitivity 0…1, mapped by the engine onto its own lux-drop and slope
    /// thresholds. The UI shows it as Subtle → Sensitive, never as raw lux.
    public var handNearSensitivity: Double
    /// Seconds the panel stays open after the hand leaves, before it retracts.
    public var autoDismissDelay: Double
    /// Camera fallback for hand-near. Opt-in only, default off.
    public var cameraFallbackEnabled: Bool
    /// Microphone fusion for taps. Opt-in only, default off.
    public var microphoneFallbackEnabled: Bool
    public var menuBarIconVisible: Bool
    public var launchAtLogin: Bool
    /// Play the system feedback sound when a tap is accepted.
    public var acknowledgementSound: Bool
    /// Global hotkey string for opening the panel without the sensor, e.g.
    /// "⌥⌘M". Stored as a display string here; the engine owns registration.
    public var panelHotkey: String?

    public init(
        handNearEnabled: Bool = true,
        handNearSensitivity: Double = 0.5,
        autoDismissDelay: Double = 2.5,
        cameraFallbackEnabled: Bool = false,
        microphoneFallbackEnabled: Bool = false,
        menuBarIconVisible: Bool = true,
        launchAtLogin: Bool = false,
        acknowledgementSound: Bool = true,
        panelHotkey: String? = "⌥⌘M"
    ) {
        self.handNearEnabled = handNearEnabled
        self.handNearSensitivity = handNearSensitivity
        self.autoDismissDelay = autoDismissDelay
        self.cameraFallbackEnabled = cameraFallbackEnabled
        self.microphoneFallbackEnabled = microphoneFallbackEnabled
        self.menuBarIconVisible = menuBarIconVisible
        self.launchAtLogin = launchAtLogin
        self.acknowledgementSound = acknowledgementSound
        self.panelHotkey = panelHotkey
    }

    public static let sensitivityRange: ClosedRange<Double> = 0...1
    public static let autoDismissRange: ClosedRange<Double> = 0.5...10
}

/// Everything the user configured, versioned so an incompatible file can be
/// explained and set aside rather than silently rewritten.
public struct MactivateConfiguration: Equatable, Codable, Sendable {
    /// Bumped whenever the meaning of stored fields changes. A file from a
    /// *newer* schema is never migrated downward; it is preserved and the UI
    /// falls back to defaults with an explanation.
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var regions: [TapRegion]
    public var bindings: [TapBinding]
    public var macroPad: MacroPad
    public var triggers: TriggerSettings
    public var updatedAt: Date

    public init(
        schemaVersion: Int = MactivateConfiguration.currentSchemaVersion,
        regions: [TapRegion],
        bindings: [TapBinding],
        macroPad: MacroPad,
        triggers: TriggerSettings = TriggerSettings(),
        updatedAt: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.regions = regions
        self.bindings = bindings
        self.macroPad = macroPad
        self.triggers = triggers
        self.updatedAt = updatedAt
    }

    public func region(_ id: TapRegionID) -> TapRegion? { regions.first { $0.id == id } }

    public func binding(region: TapRegionID, count: TapCount) -> TapBinding {
        bindings.first { $0.region == region && $0.count == count }
            ?? TapBinding(region: region, count: count)
    }

    public func bindings(for region: TapRegionID) -> [TapBinding] {
        TapCount.allCases.map { binding(region: region, count: $0) }
    }

    public var boundCount: Int {
        bindings.filter { $0.isBound && $0.isEnabled }.count
    }

    public mutating func setBinding(_ binding: TapBinding) {
        if let index = bindings.firstIndex(where: { $0.region == binding.region && $0.count == binding.count }) {
            bindings[index] = binding
        } else {
            bindings.append(binding)
        }
        updatedAt = Date()
    }

    public mutating func setAction(_ action: ActionSpec?, region: TapRegionID, count: TapCount) {
        var binding = binding(region: region, count: count)
        binding.action = action
        setBinding(binding)
    }

    public mutating func updateRegion(_ region: TapRegion) {
        if let index = regions.firstIndex(where: { $0.id == region.id }) {
            regions[index] = region
            updatedAt = Date()
        }
    }
}

/// A problem found while validating a configuration. Validation never mutates a
/// binding on its own: it reports, and the UI decides what to offer.
public struct ConfigurationIssue: Equatable, Sendable, Identifiable {
    public enum Severity: String, Sendable {
        /// The configuration cannot be used as-is.
        case blocking
        /// Usable, but something will not behave as the user expects.
        case advisory
    }

    public var id: String
    public var severity: Severity
    public var message: String
    /// What the UI can offer to do about it, phrased as a button title.
    public var suggestedFix: String?

    public init(id: String, severity: Severity, message: String, suggestedFix: String? = nil) {
        self.id = id
        self.severity = severity
        self.message = message
        self.suggestedFix = suggestedFix
    }
}

public enum ConfigurationValidator {
    public static func issues(in configuration: MactivateConfiguration) -> [ConfigurationIssue] {
        var issues: [ConfigurationIssue] = []

        if configuration.schemaVersion > MactivateConfiguration.currentSchemaVersion {
            issues.append(
                ConfigurationIssue(
                    id: "schema.newer",
                    severity: .blocking,
                    message: "This configuration was saved by a newer version of Mactivate. It has been kept unchanged and defaults are in use.",
                    suggestedFix: "Reveal Configuration File"
                )
            )
        }

        let regionIDs = Set(configuration.regions.map(\.id))
        for binding in configuration.bindings where !regionIDs.contains(binding.region) {
            issues.append(
                ConfigurationIssue(
                    id: "binding.orphan.\(binding.id)",
                    severity: .advisory,
                    message: "A binding refers to “\(binding.region.rawValue)”, which is not a calibrated region on this Mac.",
                    suggestedFix: "Remove Binding"
                )
            )
        }

        for binding in configuration.bindings {
            guard let action = binding.action else { continue }
            if action.kind == .unrecognized {
                issues.append(
                    ConfigurationIssue(
                        id: "action.unrecognized.\(binding.id)",
                        severity: .advisory,
                        message: "“\(action.title)” cannot run in this version. The binding is preserved and will not fire.",
                        suggestedFix: nil
                    )
                )
            } else if !action.missingParameters.isEmpty {
                let regionName = configuration.region(binding.region)?.name ?? binding.region.rawValue
                issues.append(
                    ConfigurationIssue(
                        id: "action.incomplete.\(binding.id)",
                        severity: .advisory,
                        message: "\(binding.count.displayName) on \(regionName) is missing \(action.missingParameters.joined(separator: ", ")).",
                        suggestedFix: "Edit Action"
                    )
                )
            }
        }

        if !TriggerSettings.sensitivityRange.contains(configuration.triggers.handNearSensitivity) {
            issues.append(
                ConfigurationIssue(
                    id: "trigger.sensitivity",
                    severity: .blocking,
                    message: "Hand-near sensitivity is outside the supported range.",
                    suggestedFix: "Reset to Default"
                )
            )
        }

        if !TriggerSettings.autoDismissRange.contains(configuration.triggers.autoDismissDelay) {
            issues.append(
                ConfigurationIssue(
                    id: "trigger.autoDismiss",
                    severity: .blocking,
                    message: "The panel dismiss delay is outside the supported range.",
                    suggestedFix: "Reset to Default"
                )
            )
        }

        return issues
    }

    public static func isUsable(_ configuration: MactivateConfiguration) -> Bool {
        !issues(in: configuration).contains { $0.severity == .blocking }
    }
}
