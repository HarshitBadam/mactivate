import Foundation
import MactuationCore
import MactivateRuntime
@testable import MactivateApp

struct TestFailure: Error, LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}

final class FakeRuntime: RuntimeControlling {
    var outputHandler: ((RuntimeOutput) -> Void)?
    private var configuration = RuntimeConfiguration.default
    var currentSnapshot = RuntimeSnapshot()
    var currentTapCalibrationProfile: RuntimeTapCalibrationProfile?
    var currentTapRegionCalibrationProfile:
        RuntimeTapRegionCalibrationProfile?
    var tapCalibrationWarning: String?
    var tapRegionCalibrationWarning: String?
    private(set) var configurationReadCount = 0
    var startCount = 0
    var stopCount = 0
    var setSpatialTapBindingError: Error?
    var setSpatialTapDispatchEnabledError: Error?

    var currentConfiguration: RuntimeConfiguration {
        configurationReadCount += 1
        return configuration
    }

    func start() {
        startCount += 1
    }

    func stop() {
        stopCount += 1
    }

    func setSpatialTapBinding(
        _ action: ActionIdentifier?,
        for gesture: PalmTapGesture
    ) throws {
        if let setSpatialTapBindingError {
            throw setSpatialTapBindingError
        }
        configuration.spatialTapBindings[gesture] = action
    }

    func setSpatialTapDispatchEnabled(_ enabled: Bool) throws {
        if let setSpatialTapDispatchEnabledError {
            throw setSpatialTapDispatchEnabledError
        }
        configuration.spatialTapDispatchEnabled = enabled
    }

    func setPanelHintsEnabled(_ enabled: Bool) throws {
        configuration.panelHintsEnabled = enabled
    }

    func resetConfiguration() throws {
        configuration = .default
    }

    func applyTapCalibration(_ profile: RuntimeTapCalibrationProfile) throws {
        currentTapCalibrationProfile = profile
    }

    func resetTapCalibration() throws {
        currentTapCalibrationProfile = nil
    }

    func applyTapRegionCalibration(
        _ profile: RuntimeTapRegionCalibrationProfile
    ) throws {
        currentTapRegionCalibrationProfile = profile
    }

    func resetTapRegionCalibration() throws {
        currentTapRegionCalibrationProfile = nil
    }
}

final class TestWorkspace: WorkspaceOpening {
    func openApplication(
        bundleIdentifier: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        completion(.success(()))
    }

    func openURL(
        _ url: URL,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        completion(.success(()))
    }
}

final class TestShortcuts: ShortcutRunning {
    func run(
        name: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        completion(.success(()))
    }

    func list(
        completion: @escaping (Result<[String], Error>) -> Void
    ) {
        completion(.success([]))
    }
}

final class TestLaunchAtLogin: LaunchAtLoginManaging {
    var status: LaunchAtLoginStatus = .disabled
    var errorToThrow: Error?

    func setEnabled(_ enabled: Bool) throws {
        if let errorToThrow {
            throw errorToThrow
        }
        status = enabled ? .enabled : .disabled
    }
}
