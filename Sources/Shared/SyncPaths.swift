import Foundation

enum SyncPaths {
    static let groupIdentifier = "group.dev.fedosov.skillssync"

    static var groupContainerURL: URL {
        if let override = ProcessInfo.processInfo.environment["SKILLS_SYNC_GROUP_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }

        if let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupIdentifier
        ) {
            return container
        }

        // Fallback keeps local/debug runs working even before app-group signing is configured.
        return URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".config")
            .appendingPathComponent("ai-agents")
            .appendingPathComponent("skillssync")
    }

    static var stateURL: URL {
        groupContainerURL.appendingPathComponent("state.json")
    }

    static var commandQueueURL: URL {
        groupContainerURL.appendingPathComponent("commands.jsonl")
    }
}
