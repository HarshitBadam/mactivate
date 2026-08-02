import Foundation
import MactuationCore

/// Fixtures for previews, the mock engine, and tests.
///
/// These exist so every state in the design — including the unhappy ones — can be
/// put on screen deliberately. A design that has only been seen in its
/// everything-works state is a design that has not been reviewed.
public enum PreviewFixtures {
    // MARK: - Capability reports

    public static func capabilities(_ scenario: EngineScenario) -> CapabilityReport {
        var states: [SensorPath: CapabilityState] = [:]
        switch scenario {
        case .unprobed:
            return .allUnknown()

        case .everythingWorks, .lowConfidence:
            states = [
                .spuAccelerometer: .available(detail: "100 Hz"),
                .spuGyroscope: .available(detail: "100 Hz"),
                .spuAmbientLight: .available(detail: "10 Hz"),
                .displayServicesAmbientLight: .available(detail: "2 Hz"),
                .microphone: .needsOptIn,
                .camera: .needsOptIn
            ]

        case .needsHelper:
            states = [
                .spuAccelerometer: .needsPrivilege(privilege: "administrator approval"),
                .spuGyroscope: .needsPrivilege(privilege: "administrator approval"),
                .spuAmbientLight: .needsPrivilege(privilege: "administrator approval"),
                .displayServicesAmbientLight: .available(detail: "2 Hz"),
                .microphone: .needsOptIn,
                .camera: .needsOptIn
            ]

        case .noTapSensor:
            states = [
                .spuAccelerometer: .unavailable(reason: "This Mac does not expose a readable motion sensor."),
                .spuGyroscope: .unavailable(reason: "This Mac does not expose a readable motion sensor."),
                .spuAmbientLight: .available(detail: "10 Hz"),
                .displayServicesAmbientLight: .available(detail: "2 Hz"),
                .microphone: .needsOptIn,
                .camera: .needsOptIn
            ]

        case .cameraFallbackOn:
            states = [
                .spuAccelerometer: .available(detail: "100 Hz"),
                .spuGyroscope: .available(detail: "100 Hz"),
                .spuAmbientLight: .unavailable(reason: "The light sensor reading did not change when the notch was covered on this Mac."),
                .displayServicesAmbientLight: .unavailable(reason: "Updates too slowly to feel like a gesture."),
                .microphone: .needsOptIn,
                .camera: .needsOptIn
            ]
        }
        return CapabilityReport(states: states)
    }

    // MARK: - Engine status

    public static func status(_ scenario: EngineScenario) -> EngineStatus {
        var status = EngineStatus(capabilities: capabilities(scenario))
        status.machineDescription = "MacBook Pro (M3 Pro) · macOS 15.4"

        switch scenario {
        case .unprobed:
            status.handNear = .undetermined
            status.tap = .undetermined
            status.helper = .notRequired
            status.probeCompletedAt = nil

        case .everythingWorks:
            status.handNear = .ready
            status.tap = .ready
            status.helper = .connected(version: "0.1.0")
            status.activeHandNearPath = .spuAmbientLight
            status.activeTapPath = .spuAccelerometer
            status.probeCompletedAt = Date(timeIntervalSinceNow: -3_600)

        case .lowConfidence:
            status.handNear = .lowConfidence(detail: "83% of waves detected in this light")
            status.tap = .ready
            status.helper = .connected(version: "0.1.0")
            status.activeHandNearPath = .spuAmbientLight
            status.activeTapPath = .spuAccelerometer
            status.probeCompletedAt = Date(timeIntervalSinceNow: -600)

        case .needsHelper:
            status.handNear = .needsPermission(permission: "the Mactivate helper")
            status.tap = .needsPermission(permission: "the Mactivate helper")
            status.helper = .disconnected(reason: "The sensor helper is not installed yet.")

        case .noTapSensor:
            status.handNear = .ready
            status.tap = .unavailable(reason: "No readable motion sensor on this Mac")
            status.helper = .connected(version: "0.1.0")
            status.activeHandNearPath = .spuAmbientLight
            status.probeCompletedAt = Date(timeIntervalSinceNow: -120)

        case .cameraFallbackOn:
            status.handNear = .ready
            status.tap = .ready
            status.helper = .connected(version: "0.1.0")
            status.activeHandNearPath = .camera
            status.activeTapPath = .spuAccelerometer
            status.probeCompletedAt = Date(timeIntervalSinceNow: -90)
            status.activeCaptures = [
                ActiveCaptureStatus(
                    path: .camera,
                    reason: "Watching for a hand near the notch, because the light sensor could not do it on this Mac.",
                    startedAt: Date(timeIntervalSinceNow: -90)
                )
            ]
        }
        return status
    }

    // MARK: - Configuration

    /// A configuration that looks like somebody has actually been using the app:
    /// a few bindings, a filled macro pad, one deliberately empty slot.
    public static func configuration(_ scenario: EngineScenario = .everythingWorks) -> MactivateConfiguration {
        var configuration = DefaultConfiguration.empty()

        let calibratedAt = Date(timeIntervalSinceNow: -7_200)
        configuration.regions = configuration.regions.map { region in
            var region = region
            switch (region.surface, region.zone) {
            case (.palmRest, .left), (.palmRest, .right):
                region.calibration = .calibrated(recall: 0.97, falseFires: 0, calibratedAt: calibratedAt)
            case (.palmRest, .center):
                region.calibration = .lowConfidence(recall: 0.78, falseFires: 1, calibratedAt: calibratedAt)
            case (.desk, .center):
                region.calibration = .calibrated(recall: 0.95, falseFires: 0, calibratedAt: calibratedAt)
            default:
                region.calibration = .uncalibrated
            }
            if scenario == .noTapSensor {
                region.calibration = .unsupported(reason: "Taps need a motion sensor this Mac does not expose.")
            }
            return region
        }

        let left = TapRegionID(surface: .palmRest, zone: .left)
        let right = TapRegionID(surface: .palmRest, zone: .right)
        let deskFront = TapRegionID(surface: .desk, zone: .center)

        configuration.bindings = [
            TapBinding(region: left, count: .single, action: ActionCatalog.screenshot(scope: "selection")),
            TapBinding(region: left, count: .double, action: ActionCatalog.openURL("https://github.com", name: "GitHub", symbol: "chevron.left.forwardslash.chevron.right")),
            TapBinding(region: left, count: .triple, action: nil),
            TapBinding(region: right, count: .single, action: ActionCatalog.keystroke("⌘⌥Space", name: "Spotlight-ish")),
            TapBinding(region: right, count: .double, action: ActionCatalog.shortcut("Start Focus", symbol: "moon.fill")),
            TapBinding(region: right, count: .triple, action: ActionCatalog.shell("open -a Terminal", name: "Terminal here")),
            TapBinding(region: deskFront, count: .single, action: ActionCatalog.keystroke("F8", name: "Play / Pause"), isEnabled: false)
        ]

        configuration.macroPad = MacroPad(pages: [
            MacroPadPage(
                title: "Daily",
                symbolName: "sun.horizon",
                slots: MacroPad.normalizedSlots([
                    MacroPadSlot(action: ActionCatalog.openURL("https://mail.google.com", name: "Mail", symbol: "envelope.fill"), label: "Mail"),
                    MacroPadSlot(action: ActionCatalog.openURL("https://github.com/pulls", name: "Pull Requests", symbol: "arrow.triangle.pull"), label: "PRs"),
                    MacroPadSlot(action: ActionCatalog.screenshot(scope: "window"), label: "Window Shot"),
                    MacroPadSlot(action: ActionCatalog.shortcut("Start Focus", symbol: "moon.fill"), label: "Focus"),
                    MacroPadSlot(action: ActionCatalog.keystroke("⌃⌘Q", name: "Lock Screen", symbol: "lock.fill"), label: "Lock"),
                    MacroPadSlot(action: ActionCatalog.shell("pmset displaysleepnow", name: "Screen Off", symbol: "display"), label: "Screen Off"),
                    MacroPadSlot()
                ])
            ),
            MacroPadPage(
                title: "Build",
                symbolName: "hammer",
                slots: MacroPad.normalizedSlots([
                    MacroPadSlot(action: ActionCatalog.shell("xcodebuild -scheme Mactivate build", name: "Build", symbol: "hammer.fill"), label: "Build"),
                    MacroPadSlot(action: ActionCatalog.shell("swift test", name: "Test", symbol: "checkmark.diamond.fill"), label: "Test"),
                    MacroPadSlot(action: ActionCatalog.openURL("https://localhost:3000", name: "Preview", symbol: "globe"), label: "Preview")
                ])
            )
        ])

        configuration.triggers.cameraFallbackEnabled = (scenario == .cameraFallbackOn)
        return configuration
    }

    // MARK: - Activity

    public static func activityFeed(_ configuration: MactivateConfiguration = configuration()) -> ActivityFeed {
        var feed = ActivityFeed()
        let left = TapRegionID(surface: .palmRest, zone: .left)
        let right = TapRegionID(surface: .palmRest, zone: .right)

        let samples: [(String, GestureEvent.Kind, Double, TimeInterval, ActionOutcome)] = [
            ("evt-4", .tap(region: left, count: .double), 0.94, -6, .ran),
            ("evt-3", .handNear, 0.88, -19, .ran),
            ("evt-2", .tap(region: right, count: .single), 0.91, -95, .ran),
            ("evt-1", .tap(region: right, count: .triple), 0.71, -600, .failed(reason: "Terminal did not respond"))
        ]

        for (id, kind, confidence, offset, outcome) in samples {
            let event = GestureEvent(
                id: id,
                kind: kind,
                confidence: confidence,
                timestamp: Date(timeIntervalSinceNow: offset)
            )
            var title: String?
            var symbol: String?
            if case .tap(let region, let count) = kind,
               let action = configuration.binding(region: region, count: count).action {
                title = action.title
                symbol = action.symbolName
            } else if case .handNear = kind {
                title = "Opened the panel"
                symbol = "hand.wave"
            }
            feed.record(ActivityEntry(event: event, actionTitle: title, actionSymbolName: symbol, outcome: outcome))
        }
        return feed
    }

    public static func calibrationResult(passing: Bool = true) -> CalibrationResult {
        passing
            ? CalibrationResult(detected: 10, attempted: 10, falseFires: 0)
            : CalibrationResult(detected: 7, attempted: 10, falseFires: 2, note: "Two fires came from typing.")
    }

    public static let display = DisplayDescription(
        size: CGSize(width: 1512, height: 982),
        notchSize: CGSize(width: 200, height: 32),
        menuBarHeight: 32
    )
}
