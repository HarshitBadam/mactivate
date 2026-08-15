import Foundation

public enum RuntimeLifecycleState: Equatable, Sendable {
    case stopped
    case starting
    case running
    case suspended
    case stopping
}

public enum TapFeatureState: Equatable, Sendable {
    case inactive
    case warmingUp
    case available(measuredRateHz: Double)
    case unavailable(reason: String)
}

public enum TapRegionFeatureState: Equatable, Sendable {
    case inactive
    case warmingUp
    case needsCalibration
    case available(profileVersion: String)
    case unavailable(reason: String)
}

public enum PanelHintFeatureState: Equatable, Sendable {
    case inactive
    case disabled
    case warmingUp
    case available
    case tooDim
    case unavailable(reason: String)
}

public struct RuntimeSnapshot: Equatable, Sendable {
    public var lifecycle: RuntimeLifecycleState
    public var tap: TapFeatureState
    public var tapRegion: TapRegionFeatureState
    public var panelHint: PanelHintFeatureState

    public init(
        lifecycle: RuntimeLifecycleState = .stopped,
        tap: TapFeatureState = .inactive,
        tapRegion: TapRegionFeatureState = .inactive,
        panelHint: PanelHintFeatureState = .inactive
    ) {
        self.lifecycle = lifecycle
        self.tap = tap
        self.tapRegion = tapRegion
        self.panelHint = panelHint
    }
}
