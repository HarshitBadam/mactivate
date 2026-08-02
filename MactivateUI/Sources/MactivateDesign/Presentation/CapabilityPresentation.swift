import Foundation
import MactuationCore

/// How a sensor path is named and explained. The names are the user's words, not
/// the engine's: nobody knows what "SPU HID ALS" means, but everybody
/// understands "Ambient light sensor (in the notch)".
public struct SensorPathPresentation: Sendable {
    public var path: SensorPath
    public var displayName: String
    public var symbolName: String
    /// One line saying what it is used for.
    public var role: String
    /// Whether using it lights up a macOS privacy indicator. Never hidden, never
    /// downplayed, and never described as something Mactivate can suppress.
    public var privacyIndicator: PrivacyIndicator
    /// Why this path is preferred or only a fallback, in the user's terms.
    public var preferenceNote: String

    public init(
        path: SensorPath,
        displayName: String,
        symbolName: String,
        role: String,
        privacyIndicator: PrivacyIndicator,
        preferenceNote: String
    ) {
        self.path = path
        self.displayName = displayName
        self.symbolName = symbolName
        self.role = role
        self.privacyIndicator = privacyIndicator
        self.preferenceNote = preferenceNote
    }
}

public enum PrivacyIndicator: Equatable, Sendable {
    case none
    case greenCamera
    case orangeMicrophone

    public var isPrivacySensitive: Bool { self != .none }

    public var explanation: String? {
        switch self {
        case .none:
            return nil
        case .greenCamera:
            return "While this is on, macOS shows the green camera indicator in the menu bar. That is macOS telling the truth about the camera being in use, and Mactivate neither hides nor can hide it."
        case .orangeMicrophone:
            return "While this is on, macOS shows the orange microphone indicator in the menu bar. That is macOS telling the truth about the microphone being in use, and Mactivate neither hides nor can hide it."
        }
    }

    public var symbolName: String {
        switch self {
        case .none: return "lock.shield"
        case .greenCamera: return "video.fill"
        case .orangeMicrophone: return "mic.fill"
        }
    }
}

/// A capability row, ready to render: title, state text, tone, and the single
/// action that would move it forward.
public struct CapabilityPresentation: Sendable {
    public var sensor: SensorPathPresentation
    public var stateText: String
    public var tone: Tone
    public var symbolName: String
    /// Button title for the one thing the user can do here, if anything.
    public var callToAction: String?
    /// Longer explanation shown under the row when it is expanded.
    public var explanation: String

    public init(
        sensor: SensorPathPresentation,
        stateText: String,
        tone: Tone,
        symbolName: String,
        callToAction: String?,
        explanation: String
    ) {
        self.sensor = sensor
        self.stateText = stateText
        self.tone = tone
        self.symbolName = symbolName
        self.callToAction = callToAction
        self.explanation = explanation
    }
}

public enum SensorPresentationCatalog {
    public static func presentation(for path: SensorPath) -> SensorPathPresentation {
        switch path {
        case .spuAccelerometer:
            return SensorPathPresentation(
                path: path,
                displayName: "Accelerometer",
                symbolName: "waveform.path.ecg",
                role: "Feels taps on the palm rests and the desk.",
                privacyIndicator: .none,
                preferenceNote: "Preferred for taps. It senses movement only — no audio, no images."
            )
        case .spuGyroscope:
            return SensorPathPresentation(
                path: path,
                displayName: "Gyroscope",
                symbolName: "gyroscope",
                role: "Helps tell a left tap from a right tap.",
                privacyIndicator: .none,
                preferenceNote: "Used alongside the accelerometer when it improves accuracy."
            )
        case .spuAmbientLight:
            return SensorPathPresentation(
                path: path,
                displayName: "Ambient light sensor",
                symbolName: "sun.max",
                role: "Notices the shadow of your hand over the notch.",
                privacyIndicator: .none,
                preferenceNote: "Preferred for the hand wave. It reads brightness only — it cannot see you."
            )
        case .displayServicesAmbientLight:
            return SensorPathPresentation(
                path: path,
                displayName: "Ambient light (display brightness)",
                symbolName: "sun.max.trianglebadge.exclamationmark",
                role: "A slower reading of the same light sensor.",
                privacyIndicator: .none,
                preferenceNote: "Used when the faster reading is unavailable. It updates less often, so the wave may feel late."
            )
        case .microphone:
            return SensorPathPresentation(
                path: path,
                displayName: "Microphone",
                symbolName: "mic",
                role: "Hears taps when movement alone is not enough.",
                privacyIndicator: .orangeMicrophone,
                preferenceNote: "A fallback you turn on yourself. Off unless you enable it."
            )
        case .camera:
            return SensorPathPresentation(
                path: path,
                displayName: "Camera",
                symbolName: "video",
                role: "Sees your hand approach the notch.",
                privacyIndicator: .greenCamera,
                preferenceNote: "A fallback you turn on yourself. Off unless you enable it."
            )
        }
    }

    /// The paths that serve the hand-wave trigger, in preference order.
    public static let handNearPaths: [SensorPath] = [.spuAmbientLight, .displayServicesAmbientLight, .camera]
    /// The paths that serve tap detection, in preference order.
    public static let tapPaths: [SensorPath] = [.spuAccelerometer, .spuGyroscope, .microphone]

    public static func presentation(
        for path: SensorPath,
        state: CapabilityState,
        isEnabled: Bool = false
    ) -> CapabilityPresentation {
        let sensor = presentation(for: path)

        switch state {
        case .unknown:
            return CapabilityPresentation(
                sensor: sensor,
                stateText: "Not checked",
                tone: .experimental,
                symbolName: "questionmark.circle",
                callToAction: "Check Sensors",
                explanation: "Mactivate has not yet confirmed this sensor on this Mac. Nothing is assumed until it is checked here."
            )
        case .available(let detail):
            return CapabilityPresentation(
                sensor: sensor,
                stateText: detail.isEmpty ? "Available" : detail,
                tone: .ready,
                symbolName: "checkmark.circle.fill",
                callToAction: "Test",
                explanation: "\(sensor.role) \(sensor.preferenceNote)"
            )
        case .unavailable(let reason):
            return CapabilityPresentation(
                sensor: sensor,
                stateText: "Unavailable",
                tone: .unavailable,
                symbolName: "minus.circle",
                callToAction: nil,
                explanation: "\(reason) Mactivate keeps working without it — the features that need it are turned off rather than guessed at."
            )
        case .needsPrivilege(let privilege):
            return CapabilityPresentation(
                sensor: sensor,
                stateText: "Needs \(privilege)",
                tone: .attention,
                symbolName: "lock.circle",
                callToAction: "Set Up Helper",
                explanation: "Reading this sensor requires \(privilege). Mactivate installs a small helper for that job so the app itself never runs with those privileges."
            )
        case .needsOptIn:
            let indicatorNote = sensor.privacyIndicator.explanation ?? ""
            return CapabilityPresentation(
                sensor: sensor,
                stateText: isEnabled ? "On" : "Off — your choice",
                tone: isEnabled ? .attention : .neutral,
                symbolName: sensor.privacyIndicator.symbolName,
                callToAction: isEnabled ? "Turn Off" : "Turn On…",
                explanation: "\(sensor.preferenceNote) \(indicatorNote)"
            )
        }
    }

    /// Rows for a capability list, in preference order, hand-wave paths first.
    public static func rows(from report: CapabilityReport, triggers: TriggerSettings) -> [CapabilityPresentation] {
        (handNearPaths + tapPaths).map { path in
            presentation(
                for: path,
                state: report.state(of: path),
                isEnabled: isFallbackEnabled(path, triggers: triggers)
            )
        }
    }

    public static func isFallbackEnabled(_ path: SensorPath, triggers: TriggerSettings) -> Bool {
        switch path {
        case .camera: return triggers.cameraFallbackEnabled
        case .microphone: return triggers.microphoneFallbackEnabled
        default: return true
        }
    }
}
