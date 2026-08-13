import Foundation
import MactivateRuntime

struct AppPreferences: Codable, Equatable {
    static let currentSchemaVersion = 2
    static let quickActionCount = 4

    var schemaVersion: Int
    var actions: [AppActionDefinition]
    var quickActionIDs: [ActionIdentifier?]
    var onboardingCompleted: Bool

    init(schemaVersion: Int = currentSchemaVersion,
         actions: [AppActionDefinition] = [],
         quickActionIDs: [ActionIdentifier?] = [],
         onboardingCompleted: Bool = false) {
        self.schemaVersion = schemaVersion
        self.actions = actions
        self.quickActionIDs = quickActionIDs
        self.onboardingCompleted = onboardingCompleted
    }

    static let `default` = AppPreferences()

    var normalizedQuickActionIDs: [ActionIdentifier?] {
        Array(
            (quickActionIDs + Array(
                repeating: nil,
                count: Self.quickActionCount
            )).prefix(Self.quickActionCount)
        )
    }

    var isValid: Bool {
        guard schemaVersion == Self.currentSchemaVersion,
              quickActionIDs.count <= Self.quickActionCount,
              actions.allSatisfy({ action in
                  guard action.isValid,
                        action.id != AppActionDefinition.showPanel.id else {
                      return false
                  }
                  if case .showPanel = action.kind { return false }
                  return true
              }),
              Set(actions.map(\.id)).count == actions.count else {
            return false
        }
        let knownIDs = Set(actions.map(\.id))
        return normalizedQuickActionIDs.compactMap { $0 }.allSatisfy {
            knownIDs.contains($0)
        }
    }

    func migratedToCurrentSchema() -> AppPreferences {
        let validActions = actions.filter { action in
            guard action.isValid,
                  action.id != AppActionDefinition.showPanel.id else {
                return false
            }
            if case .showPanel = action.kind { return false }
            return true
        }
        var seenIDs = Set<ActionIdentifier>()
        let uniqueActions = validActions.filter {
            seenIDs.insert($0.id).inserted
        }
        let validIDs = Set(uniqueActions.map(\.id))
        return AppPreferences(
            actions: uniqueActions,
            quickActionIDs: normalizedQuickActionIDs.map {
                guard let identifier = $0,
                      identifier != AppActionDefinition.showPanel.id,
                      validIDs.contains(identifier) else {
                    return nil
                }
                return identifier
            },
            onboardingCompleted: onboardingCompleted
        )
    }
}

struct AppPreferencesLoadResult {
    let preferences: AppPreferences
    let warning: String?
}

protocol AppPreferencesStoring: AnyObject {
    func load() -> AppPreferencesLoadResult
    func save(_ preferences: AppPreferences) throws
}

enum AppPreferencesStoreError: LocalizedError {
    case invalidPreferences

    var errorDescription: String? {
        "The app preferences are invalid."
    }
}

final class UserDefaultsAppPreferencesStore: AppPreferencesStoring {
    static let defaultKey = "com.mactivate.app.preferences"

    private struct SchemaProbe: Decodable {
        let schemaVersion: Int
    }

    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard,
         key: String = UserDefaultsAppPreferencesStore.defaultKey) {
        self.defaults = defaults
        self.key = key
    }

    func load() -> AppPreferencesLoadResult {
        guard let data = defaults.data(forKey: key) else {
            return AppPreferencesLoadResult(preferences: .default, warning: nil)
        }
        do {
            let decoder = JSONDecoder()
            let probe = try decoder.decode(SchemaProbe.self, from: data)
            guard (1...AppPreferences.currentSchemaVersion).contains(
                probe.schemaVersion
            ) else {
                return AppPreferencesLoadResult(
                    preferences: .default,
                    warning: "Unsupported app preference schema; using empty app settings."
                )
            }
            let decoded = try decoder.decode(AppPreferences.self, from: data)
            let preferences = probe.schemaVersion ==
                AppPreferences.currentSchemaVersion ?
                decoded : decoded.migratedToCurrentSchema()
            guard preferences.isValid else {
                return AppPreferencesLoadResult(
                    preferences: .default,
                    warning: "Invalid app preferences; using empty app settings."
                )
            }
            if probe.schemaVersion < AppPreferences.currentSchemaVersion {
                try? save(preferences)
            }
            return AppPreferencesLoadResult(
                preferences: preferences,
                warning: nil
            )
        } catch {
            return AppPreferencesLoadResult(
                preferences: .default,
                warning: "Unreadable app preferences; using empty app settings."
            )
        }
    }

    func save(_ preferences: AppPreferences) throws {
        guard preferences.isValid else {
            throw AppPreferencesStoreError.invalidPreferences
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        defaults.set(try encoder.encode(preferences), forKey: key)
    }
}

final class InMemoryAppPreferencesStore: AppPreferencesStoring {
    var preferences: AppPreferences

    init(preferences: AppPreferences = .default) {
        self.preferences = preferences
    }

    func load() -> AppPreferencesLoadResult {
        AppPreferencesLoadResult(preferences: preferences, warning: nil)
    }

    func save(_ preferences: AppPreferences) throws {
        guard preferences.isValid else {
            throw AppPreferencesStoreError.invalidPreferences
        }
        self.preferences = preferences
    }
}
