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

    enum CodingKeys: String, CodingKey {
        case version
        case generatedAt = "generated_at"
        case sync
        case summary
        case skills
        case topSkills = "top_skills"
    }

    static let empty = SyncState(
        version: 1,
        generatedAt: "",
        sync: .empty,
        summary: .empty,
        skills: [],
        topSkills: []
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

struct SkillParsedMetadataItem: Hashable {
    let key: String
    let value: String
}

struct SkillParsedHeader: Hashable {
    let title: String
    let description: String?
    let intro: String?
    let metadata: [SkillParsedMetadataItem]
}

struct SkillRelation: Identifiable, Hashable {
    enum Kind: String, Hashable {
        case content
        case symlink
    }

    let from: String
    let to: String
    let kind: Kind

    var id: String {
        "\(kind.rawValue)|\(from)|\(to)"
    }
}

struct SkillTreeNode: Identifiable, Hashable {
    let name: String
    let relativePath: String
    let isDirectory: Bool
    let children: [SkillTreeNode]

    var id: String {
        "\(relativePath)|\(name)|\(isDirectory)"
    }
}

struct SkillPreviewData: Hashable {
    let displayTitle: String
    let header: SkillParsedHeader?
    let tree: SkillTreeNode?
    let relations: [SkillRelation]
    let mainFileBodyPreview: String?
    let isMainFileBodyPreviewTruncated: Bool
    let previewUnavailableReason: String?
}
