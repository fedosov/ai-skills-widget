import Foundation

struct SyncStateStore {
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init() {
        encoder.outputFormatting = [.sortedKeys]
    }

    func loadState() -> SyncState {
        let url = SyncPaths.stateURL
        guard let data = try? Data(contentsOf: url) else {
            return .empty
        }

        guard let state = try? decoder.decode(SyncState.self, from: data) else {
            return .empty
        }

        return state
    }

    func topSkills(from state: SyncState) -> [SkillRecord] {
        let index = Dictionary(uniqueKeysWithValues: state.skills.map { ($0.id, $0) })
        let preferred = state.topSkills.compactMap { index[$0] }
        if preferred.count >= 6 {
            return Array(preferred.prefix(6))
        }

        let fallback = state.skills.filter { skill in
            !preferred.contains(where: { $0.id == skill.id })
        }
        .sorted { lhs, rhs in
            if lhs.scope != rhs.scope {
                return lhs.scope == "global"
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        return Array((preferred + fallback).prefix(6))
    }

    func appendCommand(_ command: SyncCommand) throws {
        let url = SyncPaths.commandQueueURL
        try FileManager.default.createDirectory(
            at: SyncPaths.groupContainerURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: Data())
        }

        let payload = try encoder.encode(command)
        guard var line = String(data: payload, encoding: .utf8) else {
            throw NSError(domain: "SkillsSync", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot encode command"])
        }
        line += "\n"

        guard let bytes = line.data(using: .utf8) else {
            throw NSError(domain: "SkillsSync", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot serialize command line"])
        }

        let handle = try FileHandle(forWritingTo: url)
        defer {
            try? handle.close()
        }

        try handle.seekToEnd()
        try handle.write(contentsOf: bytes)
    }

    func makeCommand(
        type: CommandType,
        skill: SkillRecord? = nil,
        requestedBy: String,
        confirmed: Bool? = nil
    ) -> SyncCommand {
        SyncCommand(
            id: UUID().uuidString,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            type: type,
            skillId: skill?.id,
            path: skill?.canonicalSourcePath,
            requestedBy: requestedBy,
            confirmed: confirmed
        )
    }
}
