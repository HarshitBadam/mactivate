import Foundation
import MactuationCore

public enum TapCalibrationProfileLoadResult: Equatable, Sendable {
    case missing
    case loaded(TapCalibrationProfile)
    case invalid(String)

    public var profile: TapCalibrationProfile? {
        guard case .loaded(let profile) = self else { return nil }
        return profile
    }
}

public protocol TapCalibrationProfileStore: AnyObject {
    func load() -> TapCalibrationProfileLoadResult
    func save(_ profile: TapCalibrationProfile) throws
    func reset()
}

public final class UserDefaultsTapCalibrationProfileStore:
    TapCalibrationProfileStore {
    public static let defaultKey = "com.mactivate.runtime.tap-calibration"

    private let defaults: UserDefaults
    private let key: String

    public init(
        defaults: UserDefaults = .standard,
        key: String = UserDefaultsTapCalibrationProfileStore.defaultKey
    ) {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> TapCalibrationProfileLoadResult {
        guard let data = defaults.data(forKey: key) else { return .missing }
        do {
            let profile = try JSONDecoder().decode(
                TapCalibrationProfile.self,
                from: data
            )
            guard profile.schemaVersion ==
                    TapCalibrationProfile.currentSchemaVersion else {
                return .invalid(
                    "Tap calibration must be repeated after this update."
                )
            }
            guard profile.isValid else {
                return .invalid("The saved palm-tap calibration is invalid.")
            }
            return .loaded(profile)
        } catch {
            return .invalid("The saved palm-tap calibration is unreadable.")
        }
    }

    public func save(_ profile: TapCalibrationProfile) throws {
        guard profile.isValid else {
            throw RuntimeConfigurationStoreError.invalidConfiguration(
                "tap calibration must contain both palm rests and both force levels"
            )
        }
        defaults.set(try JSONEncoder().encode(profile), forKey: key)
    }

    public func reset() {
        defaults.removeObject(forKey: key)
    }
}

public final class InMemoryTapCalibrationProfileStore:
    TapCalibrationProfileStore {
    private let lock = NSLock()
    private var result: TapCalibrationProfileLoadResult

    public init(result: TapCalibrationProfileLoadResult = .missing) {
        self.result = result
    }

    public func load() -> TapCalibrationProfileLoadResult {
        lock.withLock { result }
    }

    public func save(_ profile: TapCalibrationProfile) throws {
        guard profile.isValid else {
            throw RuntimeConfigurationStoreError.invalidConfiguration(
                "invalid tap calibration"
            )
        }
        lock.withLock { result = .loaded(profile) }
    }

    public func reset() {
        lock.withLock { result = .missing }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
