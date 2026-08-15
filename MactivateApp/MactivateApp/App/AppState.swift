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
    @Published var tapCalibrationStoreWarning: String?
    @Published var tapRegionCalibrationProfile:
        RuntimeTapRegionCalibrationProfile?
    @Published var tapRegionCalibrationDraft = TapRegionCalibrationDraft()
    @Published var tapRegionCalibrationTarget: TapRegionCalibrationTarget?
    @Published var tapRegionCalibrationError: String?
    @Published var tapRegionCalibrationStoreWarning: String?
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
            return "Connecting palm rest sensor"
        case .available(let rate):
            let readiness = tapCalibrationProfile?.isValid == true ?
                "Palm taps ready" : "Sensor connected"
            return "\(readiness) at \(Int(rate.rounded())) Hz"
        case .unavailable(let reason):
            return "Palm taps unavailable: \(reason)"
        }
    }

    var tapCalibrationStatus: String {
        if let target = tapCalibrationTarget {
            let count = tapCalibrationDraft.sampleCount(
                side: target.side,
                intensity: target.intensity
            )
            return "Capturing \(target.side.rawValue) " +
                "\(target.intensity.rawValue) taps (\(count)/5 valid)"
        }
        guard let profile = tapCalibrationProfile else {
            return "Calibration needed"
        }
        return profile.isValid ? "Calibrated for both palm rests" :
            "Calibration needed"
    }

    var tapRegionCalibrationStatus: String {
        if let target = tapRegionCalibrationTarget {
            let count = tapRegionCalibrationDraft.sampleCount(target: target)
            return "Capturing \(target.side.rawValue) " +
                "\(target.pattern.rawValue) taps (\(count)/5)"
        }
        guard tapCalibrationProfile?.isValid == true else {
            return "Calibrate tap acceptance first"
        }
        guard tapRegionCalibrationProfile?.isValid == true else {
            return "Left/right calibration needed"
        }
        return "Left/right double and triple taps calibrated"
    }

    var spatialGesturesReady: Bool {
        tapCalibrationProfile?.isValid == true &&
            tapRegionCalibrationProfile?.isValid == true
    }

    var canCalibrateTapRegion: Bool {
        guard tapCalibrationProfile?.isValid == true else { return false }
        if case .unavailable = snapshot.tapRegion { return false }
        return true
    }

    var tapRegionStatus: String {
        switch snapshot.tapRegion {
        case .inactive:
            return "Left/right detection is off"
        case .warmingUp:
            return "Connecting gyroscope"
        case .needsCalibration:
            return tapRegionCalibrationStatus
        case .available:
            return spatialGesturesReady
                ? "Left/right detection ready"
                : tapRegionCalibrationStatus
        case .unavailable(let reason):
            return "Left/right detection unavailable: \(reason)"
        }
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
            return "Experimental hover unavailable: \(reason)"
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
        \(tapRegionStatus)
        Region calibration: \(tapRegionCalibrationStatus)
        Last tap: \(tapFeedbackDescription)
        Region detail: \(tapRegionFeedbackDescription)
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
        case .acceptedNonActionable(let pattern):
            return "accepted \(pattern.rawValue)x for diagnostics; no action"
        case .acceptedUnmapped(let gesture):
            return "accepted \(gesture.side.rawValue) " +
                "\(gesture.pattern.rawValue), no action mapped (\(latency)s)"
        case .dispatchDisabled(let gesture):
            return "accepted \(gesture.side.rawValue) " +
                "\(gesture.pattern.rawValue), palm rest actions off (\(latency)s)"
        case .duplicate(let gesture):
            return "duplicate \(gesture.side.rawValue) " +
                "\(gesture.pattern.rawValue) ignored"
        case .spatialUnavailable(let pattern, let reason):
            return "\(pattern.rawValue) tap resolved; left/right unavailable " +
                "(\(reason.message))"
        case .dispatched(let gesture, let action):
            return "dispatched \(gesture.side.rawValue) " +
                "\(gesture.pattern.rawValue) to \(action.rawValue) " +
                "(\(latency)s)"
        }
    }

    var tapFeedbackSummary: String {
        guard let feedback = lastTapFeedback else { return "No tap detected yet" }
        switch feedback.outcome {
        case .candidate:
            return "Tap detected"
        case .rejected:
            return "Tap ignored"
        case .acceptedNonActionable(let pattern):
            return "\(Self.tapPatternName(pattern).capitalized) tap recognized"
        case .acceptedUnmapped(let gesture):
            return "\(gesture.side.rawValue.capitalized) " +
                "\(gesture.pattern.rawValue) tap recognized"
        case .dispatchDisabled(let gesture):
            return "\(gesture.side.rawValue.capitalized) " +
                "\(gesture.pattern.rawValue) tap recognized"
        case .duplicate(let gesture):
            return "Repeated \(gesture.side.rawValue) " +
                "\(gesture.pattern.rawValue) tap ignored"
        case .spatialUnavailable(let pattern, _):
            return "\(pattern.rawValue.capitalized) tap recognized"
        case .dispatched(let gesture, _):
            return "\(gesture.side.rawValue.capitalized) " +
                "\(gesture.pattern.rawValue) tap triggered an action"
        }
    }

    var tapFeedbackSummaryDetail: String {
        guard let feedback = lastTapFeedback else {
            return "Tap a palm rest to see the latest decision."
        }
        switch feedback.outcome {
        case .candidate:
            return "Waiting briefly to determine the tap count."
        case .rejected(let reason):
            return reason.guidance
        case .acceptedNonActionable:
            return "The tap was recognized; no action was expected."
        case .acceptedUnmapped:
            return "No action is assigned to this gesture."
        case .dispatchDisabled:
            return "Palm rest actions are turned off."
        case .duplicate:
            return "This gesture had already been handled."
        case .spatialUnavailable:
            return "Left/right detection was unavailable for this gesture."
        case .dispatched:
            return "The assigned action ran successfully."
        }
    }

    var tapRegionFeedbackDescription: String {
        guard let feedback = lastTapFeedback else { return "none" }
        let prediction = feedback.regionPrediction?.rawValue ?? "not evaluated"
        let feature = feedback.regionFeature.map {
            String(format: "%.5f", $0)
        } ?? "none"
        let version = feedback.regionProfileVersion ?? "none"
        let reason = feedback.regionReason?.rawValue ?? "none"
        return "side=\(prediction), count=\(feedback.memberCount), " +
            "feature=\(feature), model=\(version), reason=\(reason)"
    }

    private static func tapPatternName(_ pattern: TapPattern) -> String {
        switch pattern {
        case .single: return "single"
        case .double: return "double"
        case .triple: return "triple"
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
