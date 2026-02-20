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

enum SkillLifecycleStatus: String, Codable, Hashable {
    case active
    case archived
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
    let status: SkillLifecycleStatus
    let archivedAt: String?
    let archivedBundlePath: String?
    let archivedOriginalScope: String?
    let archivedOriginalWorkspace: String?

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
        case status
        case archivedAt = "archived_at"
        case archivedBundlePath = "archived_bundle_path"
        case archivedOriginalScope = "archived_original_scope"
        case archivedOriginalWorkspace = "archived_original_workspace"
    }

    init(
        id: String,
        name: String,
        scope: String,
        workspace: String?,
        canonicalSourcePath: String,
        targetPaths: [String],
        exists: Bool,
        isSymlinkCanonical: Bool,
        packageType: String,
        skillKey: String,
        symlinkTarget: String,
        status: SkillLifecycleStatus = .active,
        archivedAt: String? = nil,
        archivedBundlePath: String? = nil,
        archivedOriginalScope: String? = nil,
        archivedOriginalWorkspace: String? = nil
    ) {
        self.id = id
        self.name = name
        self.scope = scope
        self.workspace = workspace
        self.canonicalSourcePath = canonicalSourcePath
        self.targetPaths = targetPaths
        self.exists = exists
        self.isSymlinkCanonical = isSymlinkCanonical
        self.packageType = packageType
        self.skillKey = skillKey
        self.symlinkTarget = symlinkTarget
        self.status = status
        self.archivedAt = archivedAt
        self.archivedBundlePath = archivedBundlePath
        self.archivedOriginalScope = archivedOriginalScope
        self.archivedOriginalWorkspace = archivedOriginalWorkspace
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        scope = try container.decode(String.self, forKey: .scope)
        workspace = try container.decodeIfPresent(String.self, forKey: .workspace)
        canonicalSourcePath = try container.decode(String.self, forKey: .canonicalSourcePath)
        targetPaths = try container.decode([String].self, forKey: .targetPaths)
        exists = try container.decode(Bool.self, forKey: .exists)
        isSymlinkCanonical = try container.decode(Bool.self, forKey: .isSymlinkCanonical)
        packageType = try container.decode(String.self, forKey: .packageType)
        skillKey = try container.decode(String.self, forKey: .skillKey)
        symlinkTarget = try container.decode(String.self, forKey: .symlinkTarget)
        status = try container.decodeIfPresent(SkillLifecycleStatus.self, forKey: .status) ?? .active
        archivedAt = try container.decodeIfPresent(String.self, forKey: .archivedAt)
        archivedBundlePath = try container.decodeIfPresent(String.self, forKey: .archivedBundlePath)
        archivedOriginalScope = try container.decodeIfPresent(String.self, forKey: .archivedOriginalScope)
        archivedOriginalWorkspace = try container.decodeIfPresent(String.self, forKey: .archivedOriginalWorkspace)
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
