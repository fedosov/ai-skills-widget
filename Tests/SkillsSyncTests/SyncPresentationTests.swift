import XCTest
@testable import SkillsSyncApp

final class SyncPresentationTests: XCTestCase {
    func testSyncStatusPresentationUsesEmpatheticTitlesAndSymbols() {
        XCTAssertEqual(SyncHealthStatus.ok.presentation.title, "Healthy")
        XCTAssertEqual(SyncHealthStatus.ok.presentation.symbol, "checkmark.circle.fill")

        XCTAssertEqual(SyncHealthStatus.syncing.presentation.title, "Sync in progress")
        XCTAssertEqual(SyncHealthStatus.syncing.presentation.symbol, "arrow.triangle.2.circlepath")

        XCTAssertEqual(SyncHealthStatus.failed.presentation.title, "Needs attention")
        XCTAssertEqual(SyncHealthStatus.failed.presentation.symbol, "exclamationmark.triangle.fill")

        XCTAssertEqual(SyncHealthStatus.unknown.presentation.title, "Waiting for first sync")
        XCTAssertEqual(SyncHealthStatus.unknown.presentation.symbol, "clock.badge.questionmark")
    }

    func testRelativeTimeFallbacksForMissingAndInvalidValues() {
        XCTAssertEqual(SyncFormatting.relativeTime(nil), "Never synced")
        XCTAssertEqual(SyncFormatting.relativeTime("invalid-date"), "Time unavailable")
    }

    func testApplyFiltersCombinesScopeAndSearch() {
        let skills = [
            makeSkill(id: "g-1", name: "Alpha", scope: "global"),
            makeSkill(id: "p-1", name: "Alpha Project", scope: "project"),
            makeSkill(id: "p-2", name: "Build Helper", scope: "project"),
            makeSkill(id: "g-2", name: "Zed", scope: "global")
        ]

        let filtered = AppViewModel.applyFilters(to: skills, query: "alpha", scopeFilter: .project)

        XCTAssertEqual(filtered.map(\.id), ["p-1"])
    }

    func testSyncFailureBannerIncludesRecoveryAndOptionalDetails() {
        let noDetails = InlineBannerPresentation.syncFailure(errorDetails: nil)
        XCTAssertEqual(noDetails.title, "Sync couldn't complete.")
        XCTAssertEqual(noDetails.recoveryActionTitle, "Sync now")
        XCTAssertEqual(noDetails.role, .error)
        XCTAssertTrue(noDetails.message.contains("Try Sync now. If this persists, open the app for details."))

        let withDetails = InlineBannerPresentation.syncFailure(errorDetails: "Connection timed out")
        XCTAssertTrue(withDetails.message.contains("Connection timed out"))
        XCTAssertTrue(withDetails.message.contains("Try Sync now."))
    }

    @MainActor
    func testFilteredSkillsRespectsScopeFilterInViewModel() {
        let viewModel = AppViewModel()
        viewModel.state = SyncState(
            version: 1,
            generatedAt: "2026-01-01T00:00:00Z",
            sync: .empty,
            summary: .empty,
            skills: [
                makeSkill(id: "g-1", name: "Global Skill", scope: "global"),
                makeSkill(id: "p-1", name: "Project Skill", scope: "project")
            ],
            topSkills: []
        )

        viewModel.scopeFilter = .all
        XCTAssertEqual(Set(viewModel.filteredSkills.map(\.id)), Set(["g-1", "p-1"]))

        viewModel.scopeFilter = .global
        XCTAssertEqual(viewModel.filteredSkills.map(\.id), ["g-1"])

        viewModel.scopeFilter = .project
        XCTAssertEqual(viewModel.filteredSkills.map(\.id), ["p-1"])
    }

    @MainActor
    func testSelectionDropsMissingIDsWhenStateChanges() {
        let viewModel = AppViewModel()
        viewModel.state = SyncState(
            version: 1,
            generatedAt: "2026-01-01T00:00:00Z",
            sync: .empty,
            summary: .empty,
            skills: [
                makeSkill(id: "g-1", name: "Global Skill", scope: "global"),
                makeSkill(id: "p-1", name: "Project Skill", scope: "project")
            ],
            topSkills: []
        )
        viewModel.selectedSkillIDs = Set(["g-1", "missing"])

        viewModel.pruneSelectionToCurrentSkills()

        XCTAssertEqual(viewModel.selectedSkillIDs, Set(["g-1"]))
    }

    @MainActor
    func testSingleSelectedSkillAndSelectedSkillsAreComputedFromSelection() {
        let g1 = makeSkill(id: "g-1", name: "Global Skill", scope: "global")
        let p1 = makeSkill(id: "p-1", name: "Project Skill", scope: "project")
        let viewModel = AppViewModel()
        viewModel.state = SyncState(
            version: 1,
            generatedAt: "2026-01-01T00:00:00Z",
            sync: .empty,
            summary: .empty,
            skills: [g1, p1],
            topSkills: []
        )

        viewModel.selectedSkillIDs = Set(["g-1"])
        XCTAssertEqual(viewModel.singleSelectedSkill?.id, "g-1")
        XCTAssertEqual(viewModel.selectedSkills.map(\.id), ["g-1"])

        viewModel.selectedSkillIDs = Set(["g-1", "p-1"])
        XCTAssertNil(viewModel.singleSelectedSkill)
        XCTAssertEqual(Set(viewModel.selectedSkills.map(\.id)), Set(["g-1", "p-1"]))
    }

    @MainActor
    func testDeleteSelectedSkillsNowDeletesAllAndClearsSelection() async {
        var currentSkills = [
            makeSkill(id: "g-1", name: "One", scope: "global"),
            makeSkill(id: "g-2", name: "Two", scope: "global"),
            makeSkill(id: "g-3", name: "Three", scope: "global")
        ]
        let engine = MockSyncEngine { skill in
            currentSkills.removeAll(where: { $0.id == skill.id })
            return Self.makeState(skills: currentSkills)
        }
        let viewModel = AppViewModel(makeEngine: { engine })
        viewModel.state = Self.makeState(skills: currentSkills)
        viewModel.selectedSkillIDs = Set(currentSkills.map(\.id))

        await viewModel.deleteSelectedSkillsNow()

        XCTAssertEqual(viewModel.state.skills.count, 0)
        XCTAssertTrue(viewModel.selectedSkillIDs.isEmpty)
        XCTAssertEqual(viewModel.localBanner?.message, "Deleted 3 of 3 selected skills.")
        XCTAssertNil(viewModel.alertMessage)
    }

    @MainActor
    func testDeleteSelectedSkillsNowContinuesOnPartialFailure() async {
        var currentSkills = [
            makeSkill(id: "g-1", name: "One", scope: "global"),
            makeSkill(id: "g-2", name: "Two", scope: "global"),
            makeSkill(id: "g-3", name: "Three", scope: "global")
        ]
        let engine = MockSyncEngine { skill in
            if skill.id == "g-2" {
                throw MockDeleteError()
            }
            currentSkills.removeAll(where: { $0.id == skill.id })
            return Self.makeState(skills: currentSkills)
        }
        let viewModel = AppViewModel(makeEngine: { engine })
        viewModel.state = Self.makeState(skills: currentSkills)
        viewModel.selectedSkillIDs = Set(currentSkills.map(\.id))

        await viewModel.deleteSelectedSkillsNow()

        XCTAssertEqual(viewModel.state.skills.map(\.id), ["g-2"])
        XCTAssertEqual(viewModel.selectedSkillIDs, Set(["g-2"]))
        XCTAssertEqual(viewModel.localBanner?.message, "Deleted 2 of 3 selected skills.")
        XCTAssertTrue(viewModel.alertMessage?.contains("Two") == true)
        XCTAssertTrue(viewModel.alertMessage?.contains("Mock delete error") == true)
    }

    @MainActor
    func testDeleteSelectedSkillsNowReportsFailureWhenAllFail() async {
        let skills = [
            makeSkill(id: "g-1", name: "One", scope: "global"),
            makeSkill(id: "g-2", name: "Two", scope: "global")
        ]
        let engine = MockSyncEngine { _ in
            throw MockDeleteError()
        }
        let viewModel = AppViewModel(makeEngine: { engine })
        viewModel.state = Self.makeState(skills: skills)
        viewModel.selectedSkillIDs = Set(skills.map(\.id))

        await viewModel.deleteSelectedSkillsNow()

        XCTAssertEqual(Set(viewModel.state.skills.map(\.id)), Set(["g-1", "g-2"]))
        XCTAssertEqual(viewModel.selectedSkillIDs, Set(["g-1", "g-2"]))
        XCTAssertNil(viewModel.localBanner)
        XCTAssertTrue(viewModel.alertMessage?.contains("Mock delete error") == true)
    }

    private func makeSkill(id: String, name: String, scope: String) -> SkillRecord {
        SkillRecord(
            id: id,
            name: name,
            scope: scope,
            workspace: scope == "project" ? "/tmp/project" : nil,
            canonicalSourcePath: "/tmp/\(id)",
            targetPaths: ["/tmp/target/\(id)"],
            exists: true,
            isSymlinkCanonical: true,
            packageType: "dir",
            skillKey: name.lowercased(),
            symlinkTarget: "/tmp/\(id)"
        )
    }

    private static func makeState(skills: [SkillRecord]) -> SyncState {
        SyncState(
            version: 1,
            generatedAt: "2026-01-01T00:00:00Z",
            sync: .empty,
            summary: .empty,
            skills: skills,
            topSkills: []
        )
    }
}

private struct MockDeleteError: LocalizedError {
    var errorDescription: String? { "Mock delete error" }
}

private final class MockSyncEngine: SyncEngineControlling {
    private let onDelete: (SkillRecord) async throws -> SyncState

    init(onDelete: @escaping (SkillRecord) async throws -> SyncState) {
        self.onDelete = onDelete
    }

    func runSync(trigger: SyncTrigger) async throws -> SyncState {
        .empty
    }

    func openInZed(skill: SkillRecord) throws { }

    func revealInFinder(skill: SkillRecord) throws { }

    func deleteCanonicalSource(skill: SkillRecord, confirmed: Bool) async throws -> SyncState {
        try await onDelete(skill)
    }
}
