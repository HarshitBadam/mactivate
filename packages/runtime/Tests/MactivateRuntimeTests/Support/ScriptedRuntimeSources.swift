import Foundation
import MactuationCore
@testable import MactivateRuntime

final class ScriptedSensorSource: SensorSource {
    let paths: [SensorPath]
    var startError: Error?
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private var handler: ((SensorSourceEvent) -> Void)?

    init(paths: [SensorPath], startError: Error? = nil) {
        self.paths = paths
        self.startError = startError
    }

    func start(handler: @escaping (SensorSourceEvent) -> Void) throws {
        startCount += 1
        if let startError { throw startError }
        self.handler = handler
    }

    func stop() {
        stopCount += 1
    }

    func send(_ event: SensorSourceEvent) {
        handler?(event)
    }
}

final class ScriptedSourceFactory: RuntimeSourceCreating {
    private var tapSources: [ScriptedSensorSource]
    private var panelSources: [ScriptedSensorSource]
    private let tapConstructionError: Error?
    private let panelConstructionError: Error?

    init(tapSources: [ScriptedSensorSource] = [],
         tapConstructionError: Error? = nil,
         panelSources: [ScriptedSensorSource] = [],
         panelConstructionError: Error? = nil) {
        self.tapSources = tapSources
        self.tapConstructionError = tapConstructionError
        self.panelSources = panelSources
        self.panelConstructionError = panelConstructionError
    }

    func makeTapSource() throws -> any SensorSource {
        if let tapConstructionError { throw tapConstructionError }
        guard !tapSources.isEmpty else {
            throw TestFailure("no scripted tap source remains")
        }
        return tapSources.removeFirst()
    }

    func makePanelHintSource() throws -> any SensorSource {
        if let panelConstructionError { throw panelConstructionError }
        guard !panelSources.isEmpty else {
            throw TestFailure("no scripted panel source remains")
        }
        return panelSources.removeFirst()
    }
}

final class TestLifecycleMonitor: RuntimeLifecycleMonitoring {
    private var onSleep: (() -> Void)?
    private var onWake: (() -> Void)?

    func start(onSleep: @escaping () -> Void,
               onWake: @escaping () -> Void) {
        self.onSleep = onSleep
        self.onWake = onWake
    }

    func stop() {
        onSleep = nil
        onWake = nil
    }

    func fireSleep() {
        onSleep?()
    }

    func fireWake() {
        onWake?()
    }
}

struct TestFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
