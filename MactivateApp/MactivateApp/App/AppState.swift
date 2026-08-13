import Foundation
import MactivateRuntime

@MainActor
final class AppState: ObservableObject {
    @Published var snapshot = RuntimeSnapshot()
    @Published var configuration = RuntimeConfiguration.default
    @Published var preferences = AppPreferences.default
    @Published var recentWarning: String?
    @Published var actionError: String?
    @Published var availableShortcuts: [String] = []
    @Published var launchAtLoginStatus: LaunchAtLoginStatus = .disabled

    var actions: [AppActionDefinition] {
        [AppActionDefinition.showPanel] + preferences.actions
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
            return "Palm taps are warming up"
        case .available(let rate):
            return "Palm taps ready · \(Int(rate.rounded())) Hz"
        case .unavailable(let reason):
            return "Palm taps unavailable · \(reason)"
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
        \(panelHintStatus)
        Warning: \(recentWarning ?? "none")
        """
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
