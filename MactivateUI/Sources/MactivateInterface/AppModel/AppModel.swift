#if os(macOS)
import Foundation
import Observation
import MactuationCore
import MactivateDesign

/// The single main-actor coordinator behind every Mactivate surface.
///
/// Deliberately one model rather than one per screen: the notch panel, the main
/// window, and the menu bar are three views of the same live state, and three
/// copies of it would be three chances to disagree about whether the camera is on.
///
/// It owns no sensor work. Everything comes from `MactivateEngine` over async
/// streams, which keeps processing off the main thread and makes the whole UI
/// testable against the mock.
@MainActor
@Observable
public final class AppModel {
    // MARK: - Live state

    public private(set) var status: EngineStatus
    public private(set) var configuration: MactivateConfiguration
    public private(set) var activity = ActivityFeed()
    public private(set) var configurationIssues: [ConfigurationIssue] = []

    /// The most recent accepted gesture, shown as a brief acknowledgement.
    /// Cleared on a timer so the panel does not accumulate confetti.
    public private(set) var acknowledgement: ActivityEntry?

    /// Set when a save or load failed. Presented as a visible, dismissible
    /// message: a configuration change that did not persist must never look like
    /// it did.
    public private(set) var persistenceError: String?

    public private(set) var isProbing = false
    public private(set) var calibration: CalibrationSession?

    // MARK: - Navigation and selection

    public var panel = PanelPresentation()
    public var selectedRegionID: TapRegionID?
    public var selectedPadPageID: UUID?
    public var mainWindowSection: MainWindowSection = .overview
    /// Non-nil while the action editor sheet is up.
    public var editingTarget: ActionEditTarget?

    // MARK: - Undo

    /// One-deep undo of the last configuration edit, with the label the button
    /// shows. Mapping edits must be reversible, and a snapshot is the simplest
    /// honest way to do that.
    public private(set) var undoLabel: String?
    private var undoSnapshot: MactivateConfiguration?

    private let engine: MactivateEngine
    private let store: ConfigurationStore
    private var streamTasks: [Task<Void, Never>] = []
    private var acknowledgementTask: Task<Void, Never>?
    private var calibrationTask: Task<Void, Never>?

    public init(
        engine: MactivateEngine,
        store: ConfigurationStore,
        configuration: MactivateConfiguration = DefaultConfiguration.empty(),
        status: EngineStatus = EngineStatus()
    ) {
        self.engine = engine
        self.store = store
        self.configuration = configuration
        self.status = status
        self.selectedRegionID = configuration.regions.first?.id
        self.selectedPadPageID = configuration.macroPad.pages.first?.id
        self.configurationIssues = ConfigurationValidator.issues(in: configuration)
    }

    // MARK: - Lifecycle

    /// Loads the configuration and starts following the engine. Safe to call
    /// again after a relaunch or helper restart: streams are replaced, not
    /// stacked, so a reconnect cannot double-deliver events.
    public func start() {
        streamTasks.forEach { $0.cancel() }
        streamTasks = []

        Task { await loadConfiguration() }

        streamTasks.append(
            Task { [weak self] in
                guard let self else { return }
                let initial = await self.engine.currentStatus()
                self.apply(status: initial)
                for await status in self.engine.statusUpdates() {
                    self.apply(status: status)
                }
            }
        )

        streamTasks.append(
            Task { [weak self] in
                guard let self else { return }
                for await event in self.engine.gestureEvents() {
                    await self.handle(event)
                }
            }
        )
    }

    public func stop() {
        streamTasks.forEach { $0.cancel() }
        streamTasks = []
        acknowledgementTask?.cancel()
        calibrationTask?.cancel()
    }

    private func apply(status: EngineStatus) {
        self.status = status
    }

    // MARK: - Configuration

    private func loadConfiguration() async {
        do {
            let loaded = try await store.load()
            configuration = loaded
            configurationIssues = ConfigurationValidator.issues(in: loaded)
            selectedRegionID = loaded.regions.first?.id
            selectedPadPageID = loaded.macroPad.pages.first?.id
            persistenceError = nil
        } catch ConfigurationStoreError.incompatibleSchema(let found, let supported) {
            // Fall back to defaults *without* touching the file, so a
            // newer-version configuration is never rewritten by an older build.
            configuration = DefaultConfiguration.empty()
            configurationIssues = [
                ConfigurationIssue(
                    id: "schema.newer",
                    severity: .blocking,
                    message: "Your settings were saved by Mactivate with a newer configuration format (version \(found); this version reads \(supported)). They have been left untouched and defaults are in use.",
                    suggestedFix: store.fileURL == nil ? nil : "Reveal Configuration File"
                )
            ]
        } catch {
            configuration = DefaultConfiguration.empty()
            persistenceError = "Your settings could not be read, so defaults are in use. Nothing has been overwritten."
        }
        engineDidReceiveConfiguration()
    }

    private func engineDidReceiveConfiguration() {
        if let mock = engine as? MockEngine { mock.update(configuration: configuration) }
    }

    /// Applies an edit, records one level of undo, and persists.
    public func edit(_ label: String, _ mutate: (inout MactivateConfiguration) -> Void) {
        undoSnapshot = configuration
        undoLabel = label
        var updated = configuration
        mutate(&updated)
        updated.updatedAt = Date()
        configuration = updated
        configurationIssues = ConfigurationValidator.issues(in: updated)
        engineDidReceiveConfiguration()
        persist()
    }

    public func undoLastEdit() {
        guard let snapshot = undoSnapshot else { return }
        configuration = snapshot
        configurationIssues = ConfigurationValidator.issues(in: snapshot)
        undoSnapshot = nil
        undoLabel = nil
        engineDidReceiveConfiguration()
        persist()
    }

    private func persist() {
        let snapshot = configuration
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.store.save(snapshot)
                self.persistenceError = nil
            } catch {
                self.persistenceError = "Your change could not be saved. It is still in effect for now, but it will be lost when Mactivate quits."
            }
        }
    }

    public func dismissPersistenceError() {
        persistenceError = nil
    }

    // MARK: - Bindings

    public func setAction(_ action: ActionSpec?, region: TapRegionID, count: TapCount) {
        let regionName = configuration.region(region)?.name ?? region.rawValue
        let label = action == nil ? "Undo Remove \(count.shortName) Tap" : "Undo Change \(regionName)"
        edit(label) { $0.setAction(action, region: region, count: count) }
    }

    public func setBindingEnabled(_ isEnabled: Bool, region: TapRegionID, count: TapCount) {
        edit(isEnabled ? "Undo Turn On Binding" : "Undo Turn Off Binding") { configuration in
            var binding = configuration.binding(region: region, count: count)
            binding.isEnabled = isEnabled
            configuration.setBinding(binding)
        }
    }

    public func renameRegion(_ region: TapRegionID, to name: String) {
        guard var updated = configuration.region(region) else { return }
        updated.name = name
        edit("Undo Rename Region") { $0.updateRegion(updated) }
    }

    // MARK: - Macro pad

    public func setPadSlot(_ slot: MacroPadSlot, pageID: UUID, index: Int) {
        edit(slot.isEmpty ? "Undo Clear Button" : "Undo Change Button") { configuration in
            guard let pageIndex = configuration.macroPad.pages.firstIndex(where: { $0.id == pageID }),
                  configuration.macroPad.pages[pageIndex].slots.indices.contains(index)
            else { return }
            configuration.macroPad.pages[pageIndex].slots[index] = slot
        }
    }

    public func addPadPage() {
        let title = "Pad \(configuration.macroPad.pages.count + 1)"
        edit("Undo Add Page") { configuration in
            configuration.macroPad.pages.append(
                MacroPadPage(title: title, slots: MacroPad.normalizedSlots([]))
            )
        }
        selectedPadPageID = configuration.macroPad.pages.last?.id
    }

    public func removePadPage(_ pageID: UUID) {
        guard configuration.macroPad.pages.count > 1 else { return }
        edit("Undo Remove Page") { configuration in
            configuration.macroPad.pages.removeAll { $0.id == pageID }
        }
        if selectedPadPageID == pageID { selectedPadPageID = configuration.macroPad.pages.first?.id }
    }

    public var selectedPadPage: MacroPadPage? {
        guard let selectedPadPageID else { return configuration.macroPad.pages.first }
        return configuration.macroPad.page(selectedPadPageID) ?? configuration.macroPad.pages.first
    }

    // MARK: - Running actions

    /// Runs a macro-pad button. The acknowledgement and the activity row come from
    /// the same path as a tap, so the pad is not a second, less honest code path.
    public func runPadSlot(_ slot: MacroPadSlot) async {
        guard let action = slot.action else { return }
        let outcome = await engine.run(action, trigger: .macroPad(slot: slot.id))
        let event = GestureEvent(
            id: "pad-\(slot.id.uuidString)-\(Date().timeIntervalSince1970)",
            kind: .macroPad(slot: slot.id),
            confidence: 1,
            timestamp: Date()
        )
        record(
            ActivityEntry(
                event: event,
                actionTitle: action.title,
                actionSymbolName: action.symbolName,
                outcome: outcome
            )
        )
    }

    /// Runs a binding's action from a "Test" button in the editor.
    public func testAction(_ action: ActionSpec) async -> ActionOutcome {
        await engine.run(action, trigger: .test)
    }

    public func setPaused(_ paused: Bool) async {
        await engine.setPaused(paused)
    }

    // MARK: - Gesture handling

    private func handle(_ event: GestureEvent) async {
        var title: String?
        var symbol: String?
        var outcome: ActionOutcome = .noBinding

        switch event.kind {
        case .tap(let region, let count):
            let binding = configuration.binding(region: region, count: count)
            if let action = binding.action, binding.isEnabled {
                title = action.title
                symbol = action.symbolName
                outcome = status.isPaused ? .skippedPaused : .ran
            }
        case .handNear:
            title = "Opened the panel"
            symbol = "hand.wave"
            outcome = .ran
            panel.handle(.handNearResolved)
        case .macroPad, .hotkey:
            outcome = .ran
        }

        record(ActivityEntry(event: event, actionTitle: title, actionSymbolName: symbol, outcome: outcome))
    }

    private func record(_ entry: ActivityEntry) {
        // A duplicate event ID never becomes a second acknowledgement, which is
        // the exactly-once rule as the user experiences it.
        guard activity.record(entry) else { return }
        acknowledgement = entry
        acknowledgementTask?.cancel()
        acknowledgementTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Motion.Duration.acknowledgementHold * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.acknowledgement = nil
        }
    }

    public func clearActivity() {
        activity.clear()
    }

    // MARK: - Capabilities and calibration

    public func runProbe() async {
        isProbing = true
        _ = await engine.runCapabilityProbe()
        isProbing = false
    }

    public func signalStream(for path: SensorPath) -> AsyncStream<Double> {
        engine.signalStream(for: path)
    }

    public func beginCalibration(_ subject: CalibrationSession.Subject) {
        calibrationTask?.cancel()
        calibration = CalibrationSession(subject: subject)

        let stream: AsyncStream<CalibrationProgress>
        switch subject {
        case .tap(let region, let count):
            stream = engine.calibrate(region: region, count: count)
        case .handNear:
            stream = engine.calibrateHandNear()
        }

        calibrationTask = Task { [weak self] in
            for await progress in stream {
                guard let self, !Task.isCancelled else { return }
                self.calibration?.apply(progress)
                if case .finished(let result) = progress {
                    self.applyCalibrationResult(result, subject: subject)
                }
            }
        }
    }

    public func cancelCalibration() {
        calibrationTask?.cancel()
        calibrationTask = nil
        calibration = nil
        Task { await engine.cancelCalibration() }
    }

    public func dismissCalibrationSummary() {
        calibration = nil
    }

    private func applyCalibrationResult(_ result: CalibrationResult, subject: CalibrationSession.Subject) {
        guard case .tap(let regionID, _) = subject, var region = configuration.region(regionID) else { return }
        region.calibration = result.regionCalibrationState()
        edit("Undo Calibration") { $0.updateRegion(region) }
    }

    // MARK: - Privacy fallbacks

    /// Turning a fallback on is always the result of an explicit confirmation in
    /// the UI; this method is the only path that does it.
    public func setFallback(_ path: SensorPath, enabled: Bool) async {
        edit(enabled ? "Undo Turn On Fallback" : "Undo Turn Off Fallback") { configuration in
            switch path {
            case .camera: configuration.triggers.cameraFallbackEnabled = enabled
            case .microphone: configuration.triggers.microphoneFallbackEnabled = enabled
            default: break
            }
        }
        await engine.setFallback(path, enabled: enabled)
    }

    public func updateTriggers(_ label: String, _ mutate: (inout TriggerSettings) -> Void) {
        edit(label) { mutate(&$0.triggers) }
    }

    // MARK: - Derived presentation

    public var capabilityRows: [CapabilityPresentation] {
        SensorPresentationCatalog.rows(from: status.capabilities, triggers: configuration.triggers)
    }

    public var selectedRegion: TapRegion? {
        guard let selectedRegionID else { return configuration.regions.first }
        return configuration.region(selectedRegionID) ?? configuration.regions.first
    }

    /// True when the product's own primary interaction is not available on this
    /// Mac, which the surfaces use to lead with the menu-bar and pad paths
    /// instead of pretending the wave works.
    public var handWaveUnavailable: Bool {
        !status.handNear.isOperating
    }

    public var tapsUnavailable: Bool {
        !status.tap.isOperating
    }

    public var configurationFileURL: URL? { store.fileURL }
}

/// Sections of the main window's sidebar.
public enum MainWindowSection: String, CaseIterable, Identifiable, Sendable {
    case overview
    case taps
    case macroPad
    case calibration
    case sensors
    case privacy
    case general

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .overview: return "Overview"
        case .taps: return "Taps"
        case .macroPad: return "Macro Pad"
        case .calibration: return "Calibration"
        case .sensors: return "Sensors"
        case .privacy: return "Privacy"
        case .general: return "General"
        }
    }

    public var symbolName: String {
        switch self {
        case .overview: return "rectangle.on.rectangle"
        case .taps: return "hand.tap"
        case .macroPad: return "square.grid.2x2"
        case .calibration: return "target"
        case .sensors: return "waveform.badge.magnifyingglass"
        case .privacy: return "hand.raised"
        case .general: return "gearshape"
        }
    }
}

/// What the action editor sheet is editing.
public enum ActionEditTarget: Identifiable, Equatable, Sendable {
    case binding(region: TapRegionID, count: TapCount)
    case padSlot(pageID: UUID, index: Int)

    public var id: String {
        switch self {
        case .binding(let region, let count): return "binding-\(region.rawValue)-\(count.rawValue)"
        case .padSlot(let pageID, let index): return "pad-\(pageID.uuidString)-\(index)"
        }
    }
}
#endif
