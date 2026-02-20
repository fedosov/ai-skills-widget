import Foundation

struct SkillPreviewParser {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func parse(skill: SkillRecord, maxTreeDepth: Int = 3) -> SkillPreviewData {
        let mainSkillFile = resolveMainSkillFile(skill: skill)
        let root = skillRootURL(skill: skill, mainSkillFile: mainSkillFile)
        let symlinkRelations = extractSymlinkRelations(skill: skill)

        guard let raw = try? String(contentsOf: mainSkillFile, encoding: .utf8) else {
            return SkillPreviewData(
                displayTitle: skill.name,
                header: nil,
                tree: nil,
                relations: symlinkRelations,
                mainFileBodyPreview: nil,
                isMainFileBodyPreviewTruncated: false,
                previewUnavailableReason: "Preview unavailable: SKILL.md not found."
            )
        }

        let parsed = parseFrontmatterAndBody(raw)
        let h1 = firstHeading(in: parsed.body)
        let title = preferredTitle(frontmatter: parsed.frontmatter, heading: h1, fallback: skill.name)
        let header = extractHeaderPreview(frontmatter: parsed.frontmatter, body: parsed.body, heading: h1)
        let bodyPreview = makeBodyPreview(from: parsed.body)
        let tree = buildTree(root: root, maxDepth: maxTreeDepth)
        let contentRelations = extractContentRelations(body: parsed.body, root: root)

        let allRelations = (contentRelations + symlinkRelations).sorted { lhs, rhs in
            if lhs.kind != rhs.kind {
                return lhs.kind.rawValue < rhs.kind.rawValue
            }
            if lhs.from != rhs.from {
                return lhs.from < rhs.from
            }
            return lhs.to < rhs.to
        }

        return SkillPreviewData(
            displayTitle: title,
            header: header,
            tree: tree,
            relations: allRelations,
            mainFileBodyPreview: bodyPreview.text,
            isMainFileBodyPreviewTruncated: bodyPreview.truncated,
            previewUnavailableReason: nil
        )
    }

    func resolveMainSkillFile(skill: SkillRecord) -> URL {
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
            var value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
            value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            map[key] = value
        }

        return (map, body)
    }

    private func preferredTitle(frontmatter: [String: String], heading: String?, fallback: String) -> String {
        if let title = cleaned(frontmatter["title"]) {
            return title
        }
        if let name = cleaned(frontmatter["name"]) {
            return name
        }
        if let heading = cleaned(heading) {
            return heading
        }
        return fallback
    }

    private func extractHeaderPreview(frontmatter: [String: String], body: String, heading: String?) -> SkillParsedHeader? {
        let title = preferredTitle(frontmatter: frontmatter, heading: heading, fallback: "")
        guard !title.isEmpty else {
            return nil
        }

        let description = cleaned(frontmatter["description"])
        let intro = firstIntroParagraph(in: body)
        let metadata = frontmatter.keys
            .filter { !["title", "name", "description"].contains($0) }
            .sorted()
            .compactMap { key -> SkillParsedMetadataItem? in
                guard let value = cleaned(frontmatter[key]) else { return nil }
                return SkillParsedMetadataItem(key: key, value: value)
            }

        return SkillParsedHeader(title: title, description: description, intro: intro, metadata: metadata)
    }

    private func firstHeading(in body: String) -> String? {
        for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("# ") else { continue }
            return String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private func firstIntroParagraph(in body: String) -> String? {
        let lines = body.components(separatedBy: .newlines)
        guard let h1 = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("# ") }) else {
            return nil
        }

        var index = h1 + 1
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                index += 1
                continue
            }
            if trimmed.hasPrefix("#") {
                return nil
            }
            var paragraph: [String] = [trimmed]
            index += 1
            while index < lines.count {
                let next = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
                if next.isEmpty || next.hasPrefix("#") {
                    break
                }
                paragraph.append(next)
                index += 1
            }
            return paragraph.joined(separator: " ")
        }
        return nil
    }

    private func buildTree(root: URL, maxDepth: Int) -> SkillTreeNode? {
        guard fileManager.fileExists(atPath: root.path) else {
            return nil
        }

        let rootName = root.lastPathComponent.isEmpty ? "." : root.lastPathComponent
        return buildNode(url: root, root: root, name: rootName, depth: 0, maxDepth: maxDepth)
    }

    private func buildNode(url: URL, root: URL, name: String, depth: Int, maxDepth: Int) -> SkillTreeNode {
        let relativePath: String
        if standardized(url.path) == standardized(root.path) {
            relativePath = "."
        } else {
            relativePath = relativePathFromRoot(url: url, root: root)
        }

        let isDirectory = isDirectory(url)
        guard isDirectory else {
            return SkillTreeNode(name: name, relativePath: relativePath, isDirectory: false, children: [])
        }

        guard depth < maxDepth else {
            let deepCount = countEntries(in: url)
            let moreNode = SkillTreeNode(
                name: "\(deepCount) more...",
                relativePath: relativePath + "/__more__",
                isDirectory: false,
                children: []
            )
            return SkillTreeNode(name: name, relativePath: relativePath, isDirectory: true, children: deepCount > 0 ? [moreNode] : [])
        }

        let entries = (try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        let sorted = entries.sorted { lhs, rhs in
            let lDir = self.isDirectory(lhs)
            let rDir = self.isDirectory(rhs)
            if lDir != rDir {
                return lDir && !rDir
            }
            return lhs.lastPathComponent.localizedCaseInsensitiveCompare(rhs.lastPathComponent) == .orderedAscending
        }

        let children = sorted.map { child in
            buildNode(url: child, root: root, name: child.lastPathComponent, depth: depth + 1, maxDepth: maxDepth)
        }

        return SkillTreeNode(name: name, relativePath: relativePath, isDirectory: true, children: children)
    }

    private func extractContentRelations(body: String, root: URL) -> [SkillRelation] {
        let patterns: [(String, Int)] = [
            ("`((?:resources|references|scripts|assets)/[^`]+)`", 1),
            ("\\[[^\\]]+\\]\\(([^)]+)\\)", 1),
            ("\\bopen\\s+([A-Za-z0-9_./-]+)", 1)
        ]

        var hits: Set<String> = []
        for (pattern, group) in patterns {
            let regex = try? NSRegularExpression(pattern: pattern)
            let range = NSRange(body.startIndex..<body.endIndex, in: body)
            regex?.enumerateMatches(in: body, range: range) { match, _, _ in
                guard let match else { return }
                guard let captureRange = Range(match.range(at: group), in: body) else { return }
                let candidate = String(body[captureRange])
                if let normalized = normalizeRelativePath(candidate, root: root) {
                    hits.insert(normalized)
                }
            }
        }

        return hits
            .sorted()
            .map { target in
                SkillRelation(from: "SKILL.md", to: target, kind: .content)
            }
    }

    private func normalizeRelativePath(_ value: String, root: URL) -> String? {
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

        let url = root.appendingPathComponent(candidate)
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        return relativePathFromRoot(url: url, root: root)
    }

    private func extractSymlinkRelations(skill: SkillRecord) -> [SkillRelation] {
        skill.targetPaths
            .sorted()
            .map { target in
                SkillRelation(from: skill.canonicalSourcePath, to: target, kind: .symlink)
            }
    }

    private func relativePathFromRoot(url: URL, root: URL) -> String {
        let rootPath = standardized(root.path)
        let targetPath = standardized(url.path)
        guard targetPath.hasPrefix(rootPath + "/") else {
            return url.lastPathComponent
        }
        return String(targetPath.dropFirst(rootPath.count + 1))
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    private func countEntries(in directory: URL) -> Int {
        guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return 0
        }
        return (enumerator.allObjects as? [URL] ?? []).count
    }

    private func standardized(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private func cleaned(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func makeBodyPreview(from body: String) -> (text: String?, truncated: Bool) {
        let normalized = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return (nil, false)
        }
        let limit = 2400
        if normalized.count <= limit {
            return (normalized, false)
        }
        let cutoff = normalized.index(normalized.startIndex, offsetBy: limit)
        let chunk = String(normalized[..<cutoff]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (chunk, true)
    }
}
