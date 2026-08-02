import Foundation
import MactuationCore

/// Which machine we are pretending to be. Every surface can be reviewed in each
/// of these, which is the point: "unavailable" and "needs approval" are states
/// the design has to handle as gracefully as "ready".
public enum EngineScenario: String, CaseIterable, Identifiable, Sendable {
    case everythingWorks
    case unprobed
    case needsHelper
    case noTapSensor
    case lowConfidence
    case cameraFallbackOn

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .everythingWorks: return "Everything works"
        case .unprobed: return "Sensors not checked yet"
        case .needsHelper: return "Helper not installed"
        case .noTapSensor: return "No motion sensor"
        case .lowConfidence: return "Hand wave unreliable"
        case .cameraFallbackOn: return "Camera fallback in use"
        }
    }
}

/// A stand-in for the real Mactuation Engine.
///
/// It produces plausible, *deterministic* streams: taps come from a seeded
/// generator and the waveform is a synthesized envelope. It is a design tool, not
/// a claim about hardware — nothing it displays says anything about what a real
/// Mac can do.
public final class MockEngine: MactivateEngine, @unchecked Sendable {
    private struct State {
        var scenario: EngineScenario
        var status: EngineStatus
        var configuration: MactivateConfiguration
        var emitsSimulatedGestures: Bool
        var statusContinuations: [UUID: AsyncStream<EngineStatus>.Continuation] = [:]
        var eventContinuations: [UUID: AsyncStream<GestureEvent>.Continuation] = [:]
        var eventCounter = 0
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
    }

    private let state: StateLock<State>

    public init(
        scenario: EngineScenario = .everythingWorks,
        configuration: MactivateConfiguration = PreviewFixtures.configuration(),
        emitsSimulatedGestures: Bool = false
    ) {
        state = StateLock(
            State(
                scenario: scenario,
                status: PreviewFixtures.status(scenario),
                configuration: configuration,
                emitsSimulatedGestures: emitsSimulatedGestures
            )
        )
    }

    // MARK: - Scenario control (design tool only)

    /// Switch the pretend machine. Drives the scenario picker that lets a
    /// reviewer walk every state of every surface.
    public func apply(scenario: EngineScenario) {
        let newStatus = PreviewFixtures.status(scenario)
        broadcastStatus { state in
            state.scenario = scenario
            state.status = newStatus
        }
    }

    public func update(configuration: MactivateConfiguration) {
        state.withLock { $0.configuration = configuration }
    }

    public func setEmitsSimulatedGestures(_ emits: Bool) {
        state.withLock { $0.emitsSimulatedGestures = emits }
    }

    /// Emit a specific gesture on demand, so the acknowledgement path can be
    /// exercised without hardware and without waiting.
    public func inject(_ event: GestureEvent) {
        let continuations = state.withLock { Array($0.eventContinuations.values) }
        continuations.forEach { $0.yield(event) }
    }

    // MARK: - MactivateEngine

    public func currentStatus() async -> EngineStatus {
        state.withLock { $0.status }
    }

    public func statusUpdates() -> AsyncStream<EngineStatus> {
        AsyncStream { continuation in
            let id = UUID()
            let snapshot = state.withLock { state -> EngineStatus in
                state.statusContinuations[id] = continuation
                return state.status
            }
            continuation.yield(snapshot)
            continuation.onTermination = { [weak self] _ in
                self?.state.withLock { $0.statusContinuations[id] = nil }
            }
        }
    }

    public func gestureEvents() -> AsyncStream<GestureEvent> {
        AsyncStream { continuation in
            let id = UUID()
            let shouldSimulate = state.withLock { state -> Bool in
                state.eventContinuations[id] = continuation
                return state.emitsSimulatedGestures
            }

            let task: Task<Void, Never>? = shouldSimulate
                ? Task { [weak self] in
                    while !Task.isCancelled {
                        try? await Task.sleep(nanoseconds: 5_000_000_000)
                        guard let self else { return }
                        if let event = self.makeSimulatedTap() { continuation.yield(event) }
                    }
                }
                : nil

            continuation.onTermination = { [weak self] _ in
                task?.cancel()
                self?.state.withLock { $0.eventContinuations[id] = nil }
            }
        }
    }

    public func signalStream(for path: SensorPath) -> AsyncStream<Double> {
        let isAvailable = state.withLock { $0.status.capabilities.state(of: path).allowsAcquisition }
        let isTapPath = SensorPresentationCatalog.tapPaths.contains(path)

        return AsyncStream { continuation in
            let task = Task { [weak self] in
                var phase = 0.0
                while !Task.isCancelled {
                    guard let self else { return }
                    // An unavailable sensor produces a flat line. That is the
                    // honest picture, and the UI is built to show it.
                    guard isAvailable else {
                        continuation.yield(0.5)
                        try? await Task.sleep(nanoseconds: 200_000_000)
                        continue
                    }
                    phase += 0.08
                    let noise = self.nextUnitRandom() * 0.06 - 0.03
                    if isTapPath {
                        // Mostly noise floor with occasional sharp transients, so
                        // the trace reads as taps rather than as a sine wave.
                        let transient = self.nextUnitRandom() > 0.94 ? self.nextUnitRandom() * 0.45 : 0
                        continuation.yield(0.5 + noise + transient)
                    } else {
                        let drift = sin(phase * 0.35) * 0.05
                        let shadow = sin(phase) > 0.93 ? -0.32 : 0
                        continuation.yield(0.68 + drift + noise + shadow)
                    }
                    try? await Task.sleep(nanoseconds: 33_000_000)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func runCapabilityProbe() async -> CapabilityReport {
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        let scenario = state.withLock { $0.scenario }
        let report = PreviewFixtures.capabilities(scenario)
        broadcastStatus { state in
            state.status.capabilities = report
            state.status.probeCompletedAt = Date()
        }
        return report
    }

    public func calibrate(region: TapRegionID, count: TapCount) -> AsyncStream<CalibrationProgress> {
        scriptedCalibration(
            instruction: "\(count.displayName) on the spot you actually use, once the countdown ends.",
            target: 10,
            passing: state.withLock { $0.scenario } != .lowConfidence
        )
    }

    public func calibrateHandNear() -> AsyncStream<CalibrationProgress> {
        scriptedCalibration(
            instruction: "Wave your hand over the notch once the countdown ends.",
            target: 6,
            passing: state.withLock { $0.scenario } != .lowConfidence
        )
    }

    public func cancelCalibration() async {}

    public func setFallback(_ path: SensorPath, enabled: Bool) async {
        broadcastStatus { state in
            if enabled {
                state.status.activeCaptures = [
                    ActiveCaptureStatus(
                        path: path,
                        reason: SensorPresentationCatalog.presentation(for: path).role,
                        startedAt: Date()
                    )
                ]
                if path == .camera { state.status.activeHandNearPath = .camera }
            } else {
                state.status.activeCaptures.removeAll { $0.path == path }
                if path == .camera, state.status.activeHandNearPath == .camera {
                    state.status.activeHandNearPath = .spuAmbientLight
                }
            }
        }
    }

    public func setPaused(_ paused: Bool) async {
        broadcastStatus { $0.status.isPaused = paused }
    }

    public func run(_ action: ActionSpec, trigger: ActionTrigger) async -> ActionOutcome {
        if state.withLock({ $0.status.isPaused }) { return .skippedPaused }
        guard action.isRunnable else {
            return .failed(reason: "This action is missing \(action.missingParameters.joined(separator: ", ")).")
        }
        try? await Task.sleep(nanoseconds: 180_000_000)
        return .ran
    }

    // MARK: - Simulation helpers

    private func broadcastStatus(_ mutate: (inout State) -> Void) {
        let (status, continuations) = state.withLock { state -> (EngineStatus, [AsyncStream<EngineStatus>.Continuation]) in
            mutate(&state)
            return (state.status, Array(state.statusContinuations.values))
        }
        continuations.forEach { $0.yield(status) }
    }

    private func scriptedCalibration(
        instruction: String,
        target: Int,
        passing: Bool
    ) -> AsyncStream<CalibrationProgress> {
        AsyncStream { continuation in
            let task = Task { [weak self] in
                continuation.yield(.waiting(instruction: instruction))
                try? await Task.sleep(nanoseconds: 900_000_000)
                for remaining in stride(from: 3.0, through: 1.0, by: -1.0) {
                    continuation.yield(.measuringBaseline(secondsRemaining: remaining))
                    try? await Task.sleep(nanoseconds: 600_000_000)
                }
                continuation.yield(.collecting(captured: 0, target: target))

                var detected = 0
                var falseFires = 0
                for index in 1...target {
                    try? await Task.sleep(nanoseconds: 700_000_000)
                    guard let self else { return }
                    if !passing, index % 4 == 0 {
                        if index % 8 == 0 {
                            falseFires += 1
                            continuation.yield(.falseFire(count: falseFires))
                        }
                        continue
                    }
                    detected += 1
                    continuation.yield(.captured(index: detected, confidence: 0.8 + self.nextUnitRandom() * 0.2))
                }

                try? await Task.sleep(nanoseconds: 400_000_000)
                continuation.yield(
                    .finished(
                        result: CalibrationResult(
                            detected: detected,
                            attempted: target,
                            falseFires: falseFires,
                            note: falseFires > 0 ? "Some fires happened without a tap." : nil
                        )
                    )
                )
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func makeSimulatedTap() -> GestureEvent? {
        let candidate = state.withLock { state -> (TapBinding, Int)? in
            guard state.status.tap.isOperating, !state.status.isPaused else { return nil }
            let bindings = state.configuration.bindings.filter { $0.isBound && $0.isEnabled }
            guard !bindings.isEmpty else { return nil }
            state.eventCounter += 1
            let index = state.eventCounter % bindings.count
            return (bindings[index], state.eventCounter)
        }
        guard let (binding, counter) = candidate else { return nil }
        return GestureEvent(
            id: "mock-\(counter)",
            kind: .tap(region: binding.region, count: binding.count),
            confidence: 0.85 + nextUnitRandom() * 0.14,
            timestamp: Date()
        )
    }

    /// Seeded, so a recorded design walkthrough replays identically.
    private func nextUnitRandom() -> Double {
        state.withLock { state in
            state.seed = state.seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(state.seed >> 11) / Double(UInt64(1) << 53)
        }
    }
}
