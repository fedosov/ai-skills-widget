import Foundation
import XCTest
@testable import SkillsSyncApp

final class SkillsSyncSharedTests: XCTestCase {
    private var tempDir: URL!
    private var store: SyncStateStore!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        setenv("SKILLS_SYNC_GROUP_DIR", tempDir.path, 1)
        store = SyncStateStore()
    }

    override func tearDownWithError() throws {
        unsetenv("SKILLS_SYNC_GROUP_DIR")
        try? FileManager.default.removeItem(at: tempDir)
        store = nil
    }

    func testLoadStateDecoding() throws {
        let payload = """
        {
          "version": 1,
          "generated_at": "2026-01-01T00:00:00Z",
          "sync": {
            "status": "ok",
            "last_started_at": "2026-01-01T00:00:00Z",
            "last_finished_at": "2026-01-01T00:00:05Z",
            "duration_ms": 5000,
            "error": null
          },
          "summary": {
            "global_count": 2,
            "project_count": 3,
            "conflict_count": 0
          },
          "skills": [
            {
              "id": "skill-1",
              "name": "alpha",
              "scope": "global",
              "workspace": null,
              "canonical_source_path": "/tmp/alpha",
              "target_paths": ["/tmp/t1"],
              "exists": true,
              "is_symlink_canonical": false,
              "package_type": "dir",
              "skill_key": "alpha",
              "symlink_target": "/tmp/alpha"
            }
          ],
          "top_skills": ["skill-1"]
        }
        """

        let data = try XCTUnwrap(payload.data(using: .utf8))
        try data.write(to: SyncPaths.stateURL)
        let state = store.loadState()

        XCTAssertEqual(state.version, 1)
        XCTAssertEqual(state.summary.globalCount, 2)
        XCTAssertEqual(state.skills.count, 1)
        XCTAssertEqual(state.topSkills.first, "skill-1")
    }

    func testDeepLinkRoutingParsesSkillDetailsURL() {
        let route = DeepLinkParser.parse(URL(string: "skillssync://skill?id=abc-123")!)
        XCTAssertEqual(route, .skill(id: "abc-123"))
    }

    func testDeepLinkRoutingParsesOpenURL() {
        let route = DeepLinkParser.parse(URL(string: "skillssync://open")!)
        XCTAssertEqual(route, .open)
    }

    func testDeepLinkRoutingRejectsUnknownScheme() {
        let route = DeepLinkParser.parse(URL(string: "https://example.com")!)
        XCTAssertNil(route)
    }

    func testTopSkillsUsesPreferredAndFallbackUpToSix() {
        let skills = [
            makeSkill(id: "g1", name: "Alpha", scope: "global"),
            makeSkill(id: "g2", name: "Beta", scope: "global"),
            makeSkill(id: "g3", name: "Gamma", scope: "global"),
            makeSkill(id: "p1", name: "Delta", scope: "project"),
            makeSkill(id: "p2", name: "Epsilon", scope: "project"),
            makeSkill(id: "p3", name: "Zeta", scope: "project"),
            makeSkill(id: "p4", name: "Eta", scope: "project"),
        ]

        let state = SyncState(
            version: 1,
            generatedAt: "2026-01-01T00:00:00Z",
            sync: .empty,
            summary: .empty,
            skills: skills,
            topSkills: ["p2", "missing", "g3"]
        )

        let top = store.topSkills(from: state)

        XCTAssertEqual(top.count, 6)
        XCTAssertEqual(top.first?.id, "p2")
        XCTAssertEqual(top[1].id, "g3")
        XCTAssertTrue(top.contains(where: { $0.id == "g1" }))
        XCTAssertTrue(top.contains(where: { $0.id == "g2" }))
    }

    func testSyncPathsFallbackUsesApplicationSupportDirectory() {
        let fallback = SyncPaths.storageDirectoryURL.path
        XCTAssertTrue(fallback.contains("/Library/Application Support/SkillsSync"))
        XCTAssertFalse(fallback.contains("/.config/ai-agents/skillssync"))
    }

    func testSkillTitlePriorityTitleThenNameThenH1ThenRecordName() throws {
        let parser = SkillPreviewParser()

        let titleDir = tempDir.appendingPathComponent("skill-title", isDirectory: true)
        try writeFile(titleDir.appendingPathComponent("SKILL.md"), contents: """
        ---
        title: Fancy Title
        name: from-name
        ---

        # Heading Title
        """)
        let titlePreview = parser.parse(skill: makeSkill(id: "s1", name: "record-name", scope: "global", sourcePath: titleDir.path))
        XCTAssertEqual(titlePreview.displayTitle, "Fancy Title")

        let nameDir = tempDir.appendingPathComponent("skill-name", isDirectory: true)
        try writeFile(nameDir.appendingPathComponent("SKILL.md"), contents: """
        ---
        name: Name Only
        ---

        # Heading Title
        """)
        let namePreview = parser.parse(skill: makeSkill(id: "s2", name: "record-name", scope: "global", sourcePath: nameDir.path))
        XCTAssertEqual(namePreview.displayTitle, "Name Only")

        let h1Dir = tempDir.appendingPathComponent("skill-h1", isDirectory: true)
        try writeFile(h1Dir.appendingPathComponent("SKILL.md"), contents: """
        # Heading Only

        body
        """)
        let h1Preview = parser.parse(skill: makeSkill(id: "s3", name: "record-name", scope: "global", sourcePath: h1Dir.path))
        XCTAssertEqual(h1Preview.displayTitle, "Heading Only")

        let fallbackDir = tempDir.appendingPathComponent("skill-fallback", isDirectory: true)
        try writeFile(fallbackDir.appendingPathComponent("SKILL.md"), contents: "body without heading")
        let fallbackPreview = parser.parse(skill: makeSkill(id: "s4", name: "record-name", scope: "global", sourcePath: fallbackDir.path))
        XCTAssertEqual(fallbackPreview.displayTitle, "record-name")
    }

    func testParseFrontmatterHeaderExtractsKnownKeysAndIntro() throws {
        let parser = SkillPreviewParser()
        let skillDir = tempDir.appendingPathComponent("skill-header", isDirectory: true)
        try writeFile(skillDir.appendingPathComponent("SKILL.md"), contents: """
        ---
        title: Header Title
        name: fallback-name
        description: One-line description.
        source: https://example.com/skill
        risk: safe
        ---

        # Main Header

        First intro paragraph for preview.

        ## Next Section
        """)

        let preview = parser.parse(skill: makeSkill(id: "s5", name: "record-name", scope: "global", sourcePath: skillDir.path))

        XCTAssertEqual(preview.header?.title, "Header Title")
        XCTAssertEqual(preview.header?.description, "One-line description.")
        XCTAssertEqual(preview.header?.intro, "First intro paragraph for preview.")
        XCTAssertEqual(preview.header?.metadata.first(where: { $0.key == "risk" })?.value, "safe")
        XCTAssertEqual(preview.header?.metadata.first(where: { $0.key == "source" })?.value, "https://example.com/skill")
    }

    func testTreeBuildLimitsToThreeLevelsAndAddsMoreNode() throws {
        let parser = SkillPreviewParser()
        let skillDir = tempDir.appendingPathComponent("skill-tree", isDirectory: true)
        try writeFile(skillDir.appendingPathComponent("SKILL.md"), contents: "# Root")
        try writeFile(skillDir.appendingPathComponent("a/b/c/d/deep.txt"), contents: "deep")
        try writeFile(skillDir.appendingPathComponent("a/b/c/peer.txt"), contents: "peer")

        let preview = parser.parse(skill: makeSkill(id: "s6", name: "record-name", scope: "global", sourcePath: skillDir.path))
        let thirdLevel = try XCTUnwrap(preview.tree?.children.first(where: { $0.name == "a" })?.children.first(where: { $0.name == "b" })?.children.first(where: { $0.name == "c" }))
        XCTAssertTrue(thirdLevel.children.contains(where: { $0.name.contains("more") }))
    }

    func testExtractContentRelationsFindsBacktickPathsAndMarkdownLinksAndOpenPattern() throws {
        let parser = SkillPreviewParser()
        let skillDir = tempDir.appendingPathComponent("skill-rel", isDirectory: true)
        try writeFile(skillDir.appendingPathComponent("resources/implementation-playbook.md"), contents: "res")
        try writeFile(skillDir.appendingPathComponent("references/guide.md"), contents: "ref")
        try writeFile(skillDir.appendingPathComponent("scripts/run.sh"), contents: "echo run")
        try writeFile(skillDir.appendingPathComponent("assets/logo.svg"), contents: "<svg/>")
        try writeFile(skillDir.appendingPathComponent("SKILL.md"), contents: """
        ---
        name: rel-skill
        ---

        Use `resources/implementation-playbook.md`.
        Read [guide](references/guide.md).
        Then open scripts/run.sh.
        Asset: `assets/logo.svg`.
        Missing: `resources/missing.md`.
        """)

        let preview = parser.parse(skill: makeSkill(id: "s7", name: "record-name", scope: "global", sourcePath: skillDir.path))
        let contentTargets = Set(preview.relations.filter { $0.kind == .content }.map(\.to))

        XCTAssertTrue(contentTargets.contains("resources/implementation-playbook.md"))
        XCTAssertTrue(contentTargets.contains("references/guide.md"))
        XCTAssertTrue(contentTargets.contains("scripts/run.sh"))
        XCTAssertTrue(contentTargets.contains("assets/logo.svg"))
        XCTAssertFalse(contentTargets.contains("resources/missing.md"))
    }

    func testPreviewFallsBackWhenSkillFileMissing() {
        let parser = SkillPreviewParser()
        let skillDir = tempDir.appendingPathComponent("skill-missing", isDirectory: true)
        try? FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        let skill = makeSkill(
            id: "s8",
            name: "record-name",
            scope: "global",
            sourcePath: skillDir.path
        )

        let preview = parser.parse(skill: skill)

        XCTAssertEqual(preview.displayTitle, "record-name")
        XCTAssertNil(preview.header)
        XCTAssertNotNil(preview.previewUnavailableReason)
        XCTAssertTrue(preview.relations.contains(where: { $0.kind == .symlink }))
    }

    private func makeSkill(id: String, name: String, scope: String, sourcePath: String? = nil) -> SkillRecord {
        SkillRecord(
            id: id,
            name: name,
            scope: scope,
            workspace: scope == "project" ? "/tmp/project" : nil,
            canonicalSourcePath: sourcePath ?? "/tmp/\(id)",
            targetPaths: ["/tmp/target/\(id)"],
            exists: true,
            isSymlinkCanonical: false,
            packageType: "dir",
            skillKey: name.lowercased(),
            symlinkTarget: "/tmp/\(id)"
        )
    }

    private func writeFile(_ path: URL, contents: String) throws {
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try XCTUnwrap(contents.data(using: .utf8)).write(to: path)
    }
}
