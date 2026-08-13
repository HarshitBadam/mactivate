import Foundation
import MactivateRuntime

@MainActor
final class AppState: ObservableObject {
    @Published var snapshot = RuntimeSnapshot()
    @Published var configuration = RuntimeConfiguration.default
    @Published var preferences = AppPreferences.default
    @Published var recentWarning: String?
    @Published var actionError: String?
    @Published var lastTapFeedback: TapFeedback?
    @Published var tapCalibrationProfile: RuntimeTapCalibrationProfile?
    @Published var tapCalibrationDraft = TapCalibrationDraft()
    @Published var tapCalibrationTarget: TapCalibrationTarget?
    @Published var tapCalibrationError: String?
    @Published var settingsFocusedSlot: Int?
    @Published var availableShortcuts: [String] = []
    @Published var launchAtLoginStatus: LaunchAtLoginStatus = .disabled

    var actions: [AppActionDefinition] {
        [AppActionDefinition.showPanel] + preferences.actions
    }

    var panelAssignableActions: [AppActionDefinition] {
        actions.filter { $0.id != AppActionDefinition.showPanel.id }
    }

    func action(for identifier: ActionIdentifier) -> AppActionDefinition? {
        actions.first { $0.id == identifier }
    }

    func actionTitle(for identifier: ActionIdentifier?) -> String {
        guard let identifier else { return "None" }
        return action(for: identifier)?.name ?? "Missing action"
    }

    var quickActions: [AppActionDefinition?] {
        preferences.normalizedQuickActionIDs.map { identifier in
            identifier.flatMap(action(for:))
        }
    }

    var tapStatus: String {
        switch snapshot.tap {
        case .inactive:
            return "Palm taps are off"
        case .warmingUp:
            return "Connecting palm-rest sensor"
        case .available(let rate):
            let readiness = tapCalibrationProfile?.isValid == true ?
                "Palm taps ready" : "Sensor connected"
            return "\(readiness) · \(Int(rate.rounded())) Hz"
        case .unavailable(let reason):
            return "Palm taps unavailable · \(reason)"
        }
    }

    var tapCalibrationStatus: String {
        if let target = tapCalibrationTarget {
            let count = tapCalibrationDraft.sampleCount(
                side: target.side,
                intensity: target.intensity
            )
            return "Capturing \(target.side.rawValue) \(target.intensity.rawValue) taps · \(count)/5 minimum"
        }
        guard let profile = tapCalibrationProfile else {
            return "Calibration needed"
        }
        return profile.isValid ? "Calibrated for both palm rests" :
            "Calibration needed"
    }

    var panelHintStatus: String {
        switch snapshot.panelHint {
        case .inactive:
            return "Experimental hover is off"
        case .disabled:
            return "Experimental hover disabled"
        case .warmingUp:
            return "Experimental hover warming up"
        case .available:
            return "Experimental hover ready"
        case .tooDim:
            return "Hover unavailable in dim light"
        case .unavailable(let reason):
            return "Experimental hover unavailable · \(reason)"
        }
    }

    var diagnosticText: String {
        let appVersion = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "development"
        let model = Self.hardwareModel() ?? "unknown"
        return """
        Mactivate \(appVersion)
        Model: \(model)
        Runtime: \(String(describing: snapshot.lifecycle))
        \(tapStatus)
        Last tap: \(tapFeedbackDescription)
        \(panelHintStatus)
        Warning: \(recentWarning ?? "none")
        """
    }

    var tapFeedbackDescription: String {
        guard let feedback = lastTapFeedback else { return "none" }
        let latency = String(format: "%.2f", feedback.resolutionLatencyS)
        switch feedback.outcome {
        case .candidate:
            return "candidate detected; waiting for tap count"
        case .rejected(let reason):
            return "rejected (\(reason.rawValue), \(latency)s)"
        case .acceptedUnmapped(let pattern):
            return "accepted \(pattern.rawValue)x, no action mapped (\(latency)s)"
        case .duplicate(let pattern):
            return "duplicate \(pattern.rawValue)x ignored"
        case .dispatched(let pattern, let action):
            return "dispatched \(pattern.rawValue)x to \(action.rawValue) (\(latency)s)"
        }
    }

    private static func hardwareModel() -> String? {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0,
              size > 0 else {
            return nil
        }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &bytes, &size, nil, 0) == 0 else {
            return nil
        }
        return String(cString: bytes)
    }
}
