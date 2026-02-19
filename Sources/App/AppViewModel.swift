import Foundation
import WidgetKit

@MainActor
final class AppViewModel: ObservableObject {
    @Published var state: SyncState = .empty
    @Published var searchText: String = ""
    @Published var selectedSkillID: String?
    @Published var alertMessage: String?

    private let store = SyncStateStore()
    private var timer: Timer?

    var filteredSkills: [SkillRecord] {
        let base = state.skills.sorted { lhs, rhs in
            if lhs.scope != rhs.scope {
                return lhs.scope == "global"
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return base
        }

        return base.filter { skill in
            skill.name.localizedCaseInsensitiveContains(query)
                || skill.scope.localizedCaseInsensitiveContains(query)
                || (skill.workspace?.localizedCaseInsensitiveContains(query) ?? false)
                || skill.canonicalSourcePath.localizedCaseInsensitiveContains(query)
        }
    }

    func start() {
        load()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.load()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func load() {
        state = store.loadState()

        if let selectedSkillID, !state.skills.contains(where: { $0.id == selectedSkillID }) {
            self.selectedSkillID = nil
        }
    }

    func queueSync() {
        queue(type: .syncNow, skill: nil, confirmed: nil)
    }

    func queueOpen(skill: SkillRecord) {
        queue(type: .openInZed, skill: skill, confirmed: nil)
    }

    func queueReveal(skill: SkillRecord) {
        queue(type: .revealInFinder, skill: skill, confirmed: nil)
    }

    func queueDelete(skill: SkillRecord) {
        queue(type: .deleteCanonicalSource, skill: skill, confirmed: true)
    }

    private func queue(type: CommandType, skill: SkillRecord?, confirmed: Bool?) {
        let command = store.makeCommand(
            type: type,
            skill: skill,
            requestedBy: "app",
            confirmed: confirmed
        )

        do {
            try store.appendCommand(command)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            alertMessage = error.localizedDescription
        }
    }
}
