import Foundation

struct SyncAppSettings: Codable, Equatable {
    let version: Int
    let autoMigrateToCanonicalSource: Bool

    enum CodingKeys: String, CodingKey {
        case version
        case autoMigrateToCanonicalSource = "auto_migrate_to_canonical_source"
    }

    static let `default` = SyncAppSettings(version: 1, autoMigrateToCanonicalSource: false)
}

struct SyncPreferencesStore {
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func loadSettings() -> SyncAppSettings {
        let url = SyncPaths.appSettingsURL
        guard let data = try? Data(contentsOf: url),
              let settings = try? decoder.decode(SyncAppSettings.self, from: data) else {
            return .default
        }
        return settings
    }

    func saveSettings(_ settings: SyncAppSettings) {
        do {
            try FileManager.default.createDirectory(at: SyncPaths.runtimeDirectoryURL, withIntermediateDirectories: true)
            let data = try encoder.encode(settings)
            try data.write(to: SyncPaths.appSettingsURL, options: [.atomic])
        } catch {
            // Preferences persistence should never crash sync/UI flows.
        }
    }
}
