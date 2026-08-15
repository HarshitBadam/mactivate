import Foundation
import MactuationCore

public enum TapRegionCalibrationProfileLoadResult: Equatable, Sendable {
    case missing
    case loaded(TapRegionCalibrationProfile)
    case invalid(String)

    public var profile: TapRegionCalibrationProfile? {
        guard case .loaded(let profile) = self else { return nil }
        return profile
    }

    public var warning: String? {
        guard case .invalid(let warning) = self else { return nil }
        return warning
    }
}

public protocol TapRegionCalibrationProfileStore: AnyObject {
    func load() -> TapRegionCalibrationProfileLoadResult
    func save(_ profile: TapRegionCalibrationProfile) throws
    func reset()
}

public final class UserDefaultsTapRegionCalibrationProfileStore:
    TapRegionCalibrationProfileStore {
    public static let defaultKey =
        "com.mactivate.runtime.tap-region-calibration"

    private struct SchemaProbe: Decodable {
        let schemaVersion: Int
    }

    private let defaults: UserDefaults
    private let key: String

    public init(
        defaults: UserDefaults = .standard,
        key: String = defaultKey
    ) {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> TapRegionCalibrationProfileLoadResult {
        guard let data = defaults.data(forKey: key) else { return .missing }
        do {
            let decoder = JSONDecoder()
            let schema = try decoder.decode(SchemaProbe.self, from: data)
            guard schema.schemaVersion ==
                    TapRegionCalibrationProfile.currentSchemaVersion else {
                return .invalid(
                    "The saved left/right calibration uses an unsupported " +
                        "version and was preserved."
                )
            }
            let profile = try decoder.decode(
                TapRegionCalibrationProfile.self,
                from: data
            )
            guard profile.isValid else {
                return .invalid(
                    "The saved left/right calibration is invalid and was preserved."
                )
            }
            return .loaded(profile)
        } catch {
            return .invalid(
                "The saved left/right calibration is unreadable and was preserved."
            )
        }
    }

    public func save(_ profile: TapRegionCalibrationProfile) throws {
        guard profile.isValid else {
            throw RuntimeConfigurationStoreError.invalidConfiguration(
                "left/right calibration is invalid"
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        defaults.set(try encoder.encode(profile), forKey: key)
    }

    public func reset() {
        defaults.removeObject(forKey: key)
    }
}

public final class InMemoryTapRegionCalibrationProfileStore:
    TapRegionCalibrationProfileStore {
    private let lock = NSLock()
    private var result: TapRegionCalibrationProfileLoadResult

    public init(
        result: TapRegionCalibrationProfileLoadResult = .missing
    ) {
        self.result = result
    }

    public func load() -> TapRegionCalibrationProfileLoadResult {
        lock.withLock { result }
    }

    public func save(_ profile: TapRegionCalibrationProfile) throws {
        guard profile.isValid else {
            throw RuntimeConfigurationStoreError.invalidConfiguration(
                "invalid left/right calibration"
            )
        }
        lock.withLock { result = .loaded(profile) }
    }

    public func reset() {
        lock.withLock { result = .missing }
    }
}
