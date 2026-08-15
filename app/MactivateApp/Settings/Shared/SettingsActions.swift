import MactivateRuntime

struct SettingsActions {
    let setSpatialTapBinding: (ActionIdentifier?, PalmTapGesture) -> Void
    let setSpatialTapDispatchEnabled: (Bool) -> Void
    let setPanelHintsEnabled: (Bool) -> Void
    let setQuickAction: (Int, ActionIdentifier?) -> Void
    let addApplication: () -> Bool
    let addWebURL: (String, String) -> Bool
    let addShortcut: (String) -> Bool
    let deleteAction: (ActionIdentifier) -> Void
    let refreshShortcuts: () -> Void
    let setLaunchAtLogin: (Bool) -> Void
    let beginCalibrationCapture: (TapCalibrationTarget) -> Void
    let stopCalibrationCapture: () -> Void
    let saveCalibration: () -> Void
    let resetCalibration: () -> Void
    let beginRegionCalibration: () -> Void
    let stopRegionCalibration: () -> Void
    let saveRegionCalibration: () -> Void
    let resetRegionCalibration: () -> Void
    let testAction: (ActionIdentifier) -> Void
    let reset: () -> Void
}
