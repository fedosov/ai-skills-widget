import Foundation

struct SkillValidationIssue: Identifiable, Hashable {
    let code: String
    let message: String
    let source: String?
    let line: Int?
    let details: String

    init(
        code: String,
        message: String,
        source: String? = nil,
        line: Int? = nil,
        details: String = ""
    ) {
        self.code = code
        self.message = message
        self.source = source
        self.line = line
        self.details = details
    }

    var id: String {
        "\(code)|\(message)|\(source ?? "-")|\(line ?? -1)|\(details)"
    }

    var sourceLocationText: String? {
        guard let source else { return nil }
        if let line {
            return "\(source):\(line)"
        }
        return source
    }
}

struct SkillValidationResult: Hashable {
    let issues: [SkillValidationIssue]

    var hasWarnings: Bool {
        !issues.isEmpty
    }

    var summaryText: String {
        let count = issues.count
        let noun = count == 1 ? "issue" : "issues"
        return "\(count) \(noun) found"
    }
}

struct SkillValidator {
    private let fileManager: FileManager
    private struct BrokenReferenceHit: Hashable {
        let path: String
        let line: Int
    }

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func validate(skill: SkillRecord) -> SkillValidationResult {
        let mainFile = resolveMainSkillFile(skill: skill)
        let root = skillRootURL(skill: skill, mainSkillFile: mainFile)
        var issues: [SkillValidationIssue] = []

        if isSymbolicLink(mainFile) {
            if let target = symlinkDestination(of: mainFile) {
                if fileManager.fileExists(atPath: target.path) {
                    issues.append(
                        SkillValidationIssue(
                            code: "skill_md_is_symlink",
                            message: "SKILL.md is a symlink",
                            source: mainFile.path,
                            line: 1,
                            details: "This skill uses a symlinked SKILL.md target: \(target.path)."
                        )
                    )
                } else {
                    issues.append(
                        SkillValidationIssue(
                            code: "broken_skill_md_symlink",
                            message: "SKILL.md symlink is broken",
                            source: mainFile.path,
                            line: 1,
                            details: "Symlink target does not exist: \(target.path)."
                        )
                    )
                    return SkillValidationResult(issues: issues)
                }
            } else {
                issues.append(
                    SkillValidationIssue(
                        code: "broken_skill_md_symlink",
                        message: "SKILL.md symlink is broken",
                        source: mainFile.path,
                        line: 1,
                        details: "Symlink destination cannot be resolved."
                    )
                )
                return SkillValidationResult(issues: issues)
            }
        }

        guard fileManager.fileExists(atPath: mainFile.path), !isDirectory(mainFile) else {
            let issue = SkillValidationIssue(
                code: skill.packageType == "dir" ? "missing_skill_md" : "missing_main_file",
                message: skill.packageType == "dir"
                    ? "SKILL.md not found at \(mainFile.path)"
                    : "Main file not found at \(mainFile.path)",
                source: mainFile.path,
                line: 1,
                details: "The expected main skill file is missing on disk."
            )
            return SkillValidationResult(issues: [issue])
        }

        guard let raw = try? String(contentsOf: mainFile, encoding: .utf8) else {
            let issue = SkillValidationIssue(
                code: "unreadable_utf8_main_file",
                message: "Main file cannot be read as UTF-8",
                source: mainFile.path,
                line: 1,
                details: "Check encoding or file permissions."
            )
            return SkillValidationResult(issues: issues + [issue])
        }

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            issues.append(
                SkillValidationIssue(
                    code: "empty_main_file",
                    message: "Main file is empty",
                    source: mainFile.path,
                    line: 1,
                    details: "SKILL.md has no meaningful content."
                )
            )
            return SkillValidationResult(issues: issues)
        }

        let parsed = parseFrontmatterAndBody(raw)
        if !hasTitle(frontmatter: parsed.frontmatter, body: parsed.body) {
            issues.append(
                SkillValidationIssue(
                    code: "missing_title",
                    message: "No title found",
                    source: mainFile.path,
                    line: 1,
                    details: "Add frontmatter `title`/`name` or a top-level `#` heading."
                )
            )
        }

        let broken = brokenLocalReferences(in: raw, root: root)
        issues.append(
            contentsOf: broken.map {
                SkillValidationIssue(
                    code: "broken_reference",
                    message: "Broken reference: \($0.path)",
                    source: mainFile.path,
                    line: $0.line,
                    details: "Referenced path does not exist in this skill package."
                )
            }
        )

        return SkillValidationResult(issues: issues)
    }

    private func resolveMainSkillFile(skill: SkillRecord) -> URL {
        let source = URL(fileURLWithPath: skill.canonicalSourcePath)
        if skill.packageType == "dir" {
            return source.appendingPathComponent("SKILL.md")
        }
        return source
    }

    private func skillRootURL(skill: SkillRecord, mainSkillFile: URL) -> URL {
        if skill.packageType == "dir" {
            return URL(fileURLWithPath: skill.canonicalSourcePath, isDirectory: true)
        }
        return mainSkillFile.deletingLastPathComponent()
    }

    private func parseFrontmatterAndBody(_ text: String) -> (frontmatter: [String: String], body: String) {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        guard normalized.hasPrefix("---\n") else {
            return ([:], normalized)
        }

        let start = normalized.index(normalized.startIndex, offsetBy: 4)
        guard let endRange = normalized.range(of: "\n---", range: start..<normalized.endIndex) else {
            return ([:], normalized)
        }
        let fmRaw = String(normalized[start..<endRange.lowerBound])
        let bodyStart = endRange.upperBound
        let body = String(normalized[bodyStart...]).trimmingCharacters(in: .whitespacesAndNewlines)

        var map: [String: String] = [:]
        for line in fmRaw.split(separator: "\n", omittingEmptySubsequences: false) {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty else { continue }
            let value = line[line.index(after: colon)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            map[key] = value
        }

        return (map, body)
    }

    private func hasTitle(frontmatter: [String: String], body: String) -> Bool {
        if let title = cleaned(frontmatter["title"]), !title.isEmpty {
            return true
        }
        if let name = cleaned(frontmatter["name"]), !name.isEmpty {
            return true
        }

        for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("# "), trimmed.count > 2 {
                return true
            }
        }
        return false
    }

    private func brokenLocalReferences(in text: String, root: URL) -> [BrokenReferenceHit] {
        let patterns: [(String, Int)] = [
            ("`((?:resources|references|scripts|assets)/[^`]+)`", 1),
            ("\\[[^\\]]+\\]\\(([^)]+)\\)", 1),
            ("\\bopen\\s+([A-Za-z0-9_./-]+)", 1)
        ]

        let lines = text.components(separatedBy: .newlines)
        var missingByPath: [String: Int] = [:]

        for (index, lineText) in lines.enumerated() {
            for (pattern, group) in patterns {
                let regex = try? NSRegularExpression(pattern: pattern)
                let range = NSRange(lineText.startIndex..<lineText.endIndex, in: lineText)
                regex?.enumerateMatches(in: lineText, range: range) { match, _, _ in
                    guard let match else { return }
                    guard let captureRange = Range(match.range(at: group), in: lineText) else { return }
                    let candidate = String(lineText[captureRange])
                    guard let normalized = normalizeRelativePath(candidate) else {
                        return
                    }
                    let fullPath = root.appendingPathComponent(normalized).path
                    if !fileManager.fileExists(atPath: fullPath) {
                        let lineNumber = index + 1
                        let current = missingByPath[normalized]
                        if current == nil || lineNumber < current! {
                            missingByPath[normalized] = lineNumber
                        }
                    }
                }
            }
        }

        return missingByPath
            .map { BrokenReferenceHit(path: $0.key, line: $0.value) }
            .sorted { lhs, rhs in lhs.path < rhs.path }
    }

    private func normalizeRelativePath(_ value: String) -> String? {
        var candidate = value.trimmingCharacters(in: .whitespacesAndNewlines)
        candidate = candidate.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`<>"))
        candidate = candidate.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:"))
        guard !candidate.isEmpty else { return nil }
        guard !candidate.hasPrefix("/") else { return nil }
        guard !candidate.contains("://") else { return nil }
        if candidate.hasPrefix("./") {
            candidate.removeFirst(2)
        }
        guard !candidate.isEmpty else { return nil }
        return candidate
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    private func isSymbolicLink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }

    private func symlinkDestination(of url: URL) -> URL? {
        guard let raw = try? fileManager.destinationOfSymbolicLink(atPath: url.path) else {
            return nil
        }
        if raw.hasPrefix("/") {
            return URL(fileURLWithPath: raw)
        }
        return url.deletingLastPathComponent().appendingPathComponent(raw).standardizedFileURL
    }

    private func cleaned(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
