import Foundation

struct SyncStateStore {
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
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

    func saveState(_ state: SyncState) throws {
        try FileManager.default.createDirectory(
            at: SyncPaths.groupContainerURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        let payload = try encoder.encode(state)
        try payload.write(to: SyncPaths.stateURL, options: [.atomic])
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

}
