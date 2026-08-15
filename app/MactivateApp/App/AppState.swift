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

    var spatialGesturesReady: Bool {
        tapCalibrationProfile?.isValid == true &&
            tapRegionCalibrationProfile?.isValid == true
    }

    var canCalibrateTapRegion: Bool {
        guard tapCalibrationProfile?.isValid == true else { return false }
        if case .unavailable = snapshot.tapRegion { return false }
        return true
    }
}
