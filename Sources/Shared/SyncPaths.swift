import Foundation

enum SyncPaths {
    static var storageDirectoryURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
        return appSupport.appendingPathComponent("SkillsSync", isDirectory: true)
    }

    static var runtimeDirectoryURL: URL {
        if let override = ProcessInfo.processInfo.environment["SKILLS_SYNC_GROUP_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return storageDirectoryURL
    }

    static var stateURL: URL {
        runtimeDirectoryURL.appendingPathComponent("state.json")
    }

    static var appSettingsURL: URL {
        runtimeDirectoryURL.appendingPathComponent("app-settings.json")
    }
}
