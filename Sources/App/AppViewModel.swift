import Foundation

@MainActor
final class AppViewModel: ObservableObject {
    @Published var state: SyncState = .empty
    @Published var searchText: String = ""
    @Published var scopeFilter: ScopeFilter = .all
    @Published var selectedSkillID: String?
    @Published var alertMessage: String?
    @Published var localBanner: InlineBannerPresentation?

    private let store = SyncStateStore()
    private var timer: Timer?

    var filteredSkills: [SkillRecord] {
        Self.applyFilters(to: state.skills, query: searchText, scopeFilter: scopeFilter)
    }

    nonisolated static func applyFilters(to skills: [SkillRecord], query: String, scopeFilter: ScopeFilter) -> [SkillRecord] {
        let base = skills.sorted { lhs, rhs in
            if lhs.scope != rhs.scope {
                return lhs.scope == "global"
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        let scoped = base.filter(scopeFilter.includes)
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return scoped
        }

        return scoped.filter { skill in
            skill.name.localizedCaseInsensitiveContains(trimmedQuery)
                || skill.scope.localizedCaseInsensitiveContains(trimmedQuery)
                || (skill.workspace?.localizedCaseInsensitiveContains(trimmedQuery) ?? false)
                || skill.canonicalSourcePath.localizedCaseInsensitiveContains(trimmedQuery)
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

    func refreshSources() {
        load()
        let sourceCount = state.skills.filter { $0.scope == "global" }.count
        localBanner = InlineBannerPresentation(
            title: "Sources refreshed",
            message: "Loaded \(sourceCount) source skills.",
            symbol: "arrow.clockwise.circle.fill",
            role: .info,
            recoveryActionTitle: nil
        )
    }

    func syncNow() {
        Task {
            do {
                let engine = SyncEngine()
                state = try await engine.runSync(trigger: .manual)
                localBanner = InlineBannerPresentation(
                    title: "Sync completed",
                    message: "Skills were synchronized successfully.",
                    symbol: "checkmark.circle.fill",
                    role: .success,
                    recoveryActionTitle: nil
                )
            } catch {
                load()
                alertMessage = error.localizedDescription
            }
        }
    }

    func open(skill: SkillRecord) {
        do {
            let engine = SyncEngine()
            try engine.openInZed(skill: skill)
            localBanner = InlineBannerPresentation(
                title: "Opened in Zed",
                message: "\(skill.name) was opened in Zed.",
                symbol: "checkmark.circle.fill",
                role: .success,
                recoveryActionTitle: nil
            )
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func reveal(skill: SkillRecord) {
        do {
            let engine = SyncEngine()
            try engine.revealInFinder(skill: skill)
            localBanner = InlineBannerPresentation(
                title: "Revealed in Finder",
                message: "\(skill.name) was revealed in Finder.",
                symbol: "checkmark.circle.fill",
                role: .success,
                recoveryActionTitle: nil
            )
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func delete(skill: SkillRecord) {
        Task {
            do {
                let engine = SyncEngine()
                state = try await engine.deleteCanonicalSource(skill: skill, confirmed: true)
                localBanner = InlineBannerPresentation(
                    title: "Moved to Trash",
                    message: "\(skill.name) was moved to Trash.",
                    symbol: "checkmark.circle.fill",
                    role: .warning,
                    recoveryActionTitle: nil
                )
            } catch {
                load()
                alertMessage = error.localizedDescription
            }
        }
    }
}
