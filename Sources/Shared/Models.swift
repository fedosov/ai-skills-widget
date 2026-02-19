import Foundation

enum SyncHealthStatus: String, Codable {
    case ok
    case failed
    case syncing
    case unknown
}

struct SyncState: Codable {
    let version: Int
    let generatedAt: String
    let sync: SyncMetadata
    let summary: SyncSummary
    let skills: [SkillRecord]
    let topSkills: [String]
    let lastCommandResult: CommandResult?

    enum CodingKeys: String, CodingKey {
        case version
        case generatedAt = "generated_at"
        case sync
        case summary
        case skills
        case topSkills = "top_skills"
        case lastCommandResult = "last_command_result"
    }

    static let empty = SyncState(
        version: 1,
        generatedAt: "",
        sync: .empty,
        summary: .empty,
        skills: [],
        topSkills: [],
        lastCommandResult: nil
    )
}

struct SyncMetadata: Codable {
    let status: SyncHealthStatus
    let lastStartedAt: String?
    let lastFinishedAt: String?
    let durationMs: Int?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case status
        case lastStartedAt = "last_started_at"
        case lastFinishedAt = "last_finished_at"
        case durationMs = "duration_ms"
        case error
    }

    static let empty = SyncMetadata(
        status: .unknown,
        lastStartedAt: nil,
        lastFinishedAt: nil,
        durationMs: nil,
        error: nil
    )
}

struct SyncSummary: Codable {
    let globalCount: Int
    let projectCount: Int
    let conflictCount: Int

    enum CodingKeys: String, CodingKey {
        case globalCount = "global_count"
        case projectCount = "project_count"
        case conflictCount = "conflict_count"
    }

    static let empty = SyncSummary(globalCount: 0, projectCount: 0, conflictCount: 0)
}

struct SkillRecord: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let scope: String
    let workspace: String?
    let canonicalSourcePath: String
    let targetPaths: [String]
    let exists: Bool
    let isSymlinkCanonical: Bool
    let packageType: String
    let skillKey: String
    let symlinkTarget: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case scope
        case workspace
        case canonicalSourcePath = "canonical_source_path"
        case targetPaths = "target_paths"
        case exists
        case isSymlinkCanonical = "is_symlink_canonical"
        case packageType = "package_type"
        case skillKey = "skill_key"
        case symlinkTarget = "symlink_target"
    }
}

struct CommandResult: Codable {
    let id: String?
    let type: CommandType
    let executedAt: String
    let status: String
    let message: String

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case executedAt = "executed_at"
        case status
        case message
    }
}

enum CommandType: String, Codable {
    case syncNow = "sync_now"
    case openInZed = "open_in_zed"
    case revealInFinder = "reveal_in_finder"
    case deleteCanonicalSource = "delete_canonical_source"
}

struct SyncCommand: Codable {
    let id: String
    let createdAt: String
    let type: CommandType
    let skillId: String?
    let path: String?
    let requestedBy: String
    let confirmed: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case type
        case skillId = "skill_id"
        case path
        case requestedBy = "requested_by"
        case confirmed
    }
}
