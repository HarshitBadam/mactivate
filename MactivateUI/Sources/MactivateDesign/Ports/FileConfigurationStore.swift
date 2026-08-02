import Foundation

/// Configuration persistence: pretty-printed JSON, written atomically, with the
/// schema version checked on the way in.
///
/// Atomic writes matter here for a mundane reason — a truncated file would mean a
/// tap silently doing nothing or doing the wrong thing on next launch, which is
/// exactly the "bindings never change silently" rule.
public final class FileConfigurationStore: ConfigurationStore, @unchecked Sendable {
    private let url: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(url: URL) {
        self.url = url
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    /// `~/Library/Application Support/Mactivate/configuration.json`.
    public static func defaultURL(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("Mactivate", isDirectory: true)
            .appendingPathComponent("configuration.json")
    }

    public var fileURL: URL? { url }

    public func load() async throws -> MactivateConfiguration {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return DefaultConfiguration.empty()
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ConfigurationStoreError.unreadable(error.localizedDescription)
        }
        do {
            let configuration = try decoder.decode(MactivateConfiguration.self, from: data)
            guard configuration.schemaVersion <= MactivateConfiguration.currentSchemaVersion else {
                throw ConfigurationStoreError.incompatibleSchema(
                    found: configuration.schemaVersion,
                    supported: MactivateConfiguration.currentSchemaVersion
                )
            }
            return configuration
        } catch let error as ConfigurationStoreError {
            throw error
        } catch {
            throw ConfigurationStoreError.unreadable(
                "The configuration file could not be read: \(error.localizedDescription)"
            )
        }
    }

    public func save(_ configuration: MactivateConfiguration) async throws {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(configuration)
            // `.atomic` writes to an auxiliary file and renames it into place, so
            // an interrupted save leaves the previous configuration intact rather
            // than a truncated one.
            try data.write(to: url, options: .atomic)
        } catch {
            throw ConfigurationStoreError.unwritable(error.localizedDescription)
        }
    }
}

/// In-memory store for previews and tests.
public final class InMemoryConfigurationStore: ConfigurationStore, @unchecked Sendable {
    private struct State {
        var configuration: MactivateConfiguration
        var saveCount = 0
        var failNextSave = false
    }

    private let state: StateLock<State>

    public init(configuration: MactivateConfiguration = PreviewFixtures.configuration()) {
        state = StateLock(State(configuration: configuration))
    }

    public var fileURL: URL? { nil }

    public var saveCount: Int { state.withLock { $0.saveCount } }

    /// Makes the next save fail, so the "could not save" path can be reviewed.
    public func failNextSave() {
        state.withLock { $0.failNextSave = true }
    }

    public func load() async throws -> MactivateConfiguration {
        state.withLock { $0.configuration }
    }

    public func save(_ configuration: MactivateConfiguration) async throws {
        let shouldFail = state.withLock { state -> Bool in
            if state.failNextSave {
                state.failNextSave = false
                return true
            }
            state.configuration = configuration
            state.saveCount += 1
            return false
        }
        if shouldFail { throw ConfigurationStoreError.unwritable("Simulated save failure.") }
    }
}
