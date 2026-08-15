import Foundation

public enum RuntimeConfigurationLoadResult: Equatable, Sendable {
    case missing(defaults: RuntimeConfiguration)
    case loaded(RuntimeConfiguration)
    case invalid(failClosed: RuntimeConfiguration, reason: String)

    public var configuration: RuntimeConfiguration {
        switch self {
        case .missing(let configuration), .loaded(let configuration),
             .invalid(let configuration, _):
            return configuration
        }
    }

    public var warning: String? {
        guard case .invalid(_, let reason) = self else { return nil }
        return reason
    }
}

public enum RuntimeConfigurationStoreError: Error, Equatable {
    case invalidConfiguration(String)
}

public protocol RuntimeConfigurationStore: AnyObject {
    func load() -> RuntimeConfigurationLoadResult
    func save(_ configuration: RuntimeConfiguration) throws
}

public final class UserDefaultsRuntimeConfigurationStore:
    RuntimeConfigurationStore {
    public static let defaultKey = "com.mactivate.runtime.configuration"

    private struct SchemaProbe: Decodable {
        let schemaVersion: Int
    }

    private struct VersionOneConfiguration: Decodable {
        let schemaVersion: Int
        let tapBindings: TapBindings
        let panelHintsEnabled: Bool
    }

    private struct VersionTwoConfiguration: Decodable {
        let schemaVersion: Int
        let spatialTapBindings: SpatialTapBindings
        let panelHintsEnabled: Bool
    }

    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard,
                key: String = UserDefaultsRuntimeConfigurationStore.defaultKey) {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> RuntimeConfigurationLoadResult {
        guard let data = defaults.data(forKey: key) else {
            return .missing(defaults: .default)
        }
        do {
            let decoder = JSONDecoder()
            let schema = try decoder.decode(SchemaProbe.self, from: data)
            if schema.schemaVersion == 1 {
                let legacy = try decoder.decode(
                    VersionOneConfiguration.self,
                    from: data
                )
                let migrated = RuntimeConfiguration(
                    spatialTapBindings: SpatialTapBindings(),
                    panelHintsEnabled: legacy.panelHintsEnabled
                )
                try save(migrated)
                return .loaded(migrated)
            }
            if schema.schemaVersion == 2 {
                let legacy = try decoder.decode(
                    VersionTwoConfiguration.self,
                    from: data
                )
                let migrated = RuntimeConfiguration(
                    spatialTapBindings: legacy.spatialTapBindings,
                    spatialTapDispatchEnabled: true,
                    panelHintsEnabled: legacy.panelHintsEnabled
                )
                try save(migrated)
                return .loaded(migrated)
            }
            guard schema.schemaVersion ==
                    RuntimeConfiguration.currentSchemaVersion else {
                return .invalid(
                    failClosed: .failClosed,
                    reason: "unsupported runtime configuration schema " +
                        "\(schema.schemaVersion); preserved stored data"
                )
            }
            let configuration = try decoder.decode(
                RuntimeConfiguration.self,
                from: data
            )
            guard configuration.isCurrentAndValid else {
                return .invalid(
                    failClosed: .failClosed,
                    reason: "runtime configuration contains invalid action identifiers; " +
                        "preserved stored data"
                )
            }
            return .loaded(configuration)
        } catch {
            return .invalid(
                failClosed: .failClosed,
                reason: "runtime configuration is unreadable; preserved stored data"
            )
        }
    }

    public func save(_ configuration: RuntimeConfiguration) throws {
        guard configuration.isCurrentAndValid else {
            throw RuntimeConfigurationStoreError.invalidConfiguration(
                "only schema \(RuntimeConfiguration.currentSchemaVersion) with " +
                    "valid spatial action identifiers can be saved"
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        defaults.set(try encoder.encode(configuration), forKey: key)
    }
}

public final class InMemoryRuntimeConfigurationStore:
    RuntimeConfigurationStore {
    private let lock = NSLock()
    private var result: RuntimeConfigurationLoadResult

    public init(result: RuntimeConfigurationLoadResult = .missing(defaults: .default)) {
        self.result = result
    }

    public func load() -> RuntimeConfigurationLoadResult {
        lock.withLock { result }
    }

    public func save(_ configuration: RuntimeConfiguration) throws {
        guard configuration.isCurrentAndValid else {
            throw RuntimeConfigurationStoreError.invalidConfiguration(
                "invalid runtime configuration"
            )
        }
        lock.withLock {
            result = .loaded(configuration)
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
