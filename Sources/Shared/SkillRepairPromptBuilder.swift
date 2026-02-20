import Foundation

struct SkillRepairPromptBuilder {
    static func prompt(for skill: SkillRecord, issue: SkillValidationIssue) -> String {
        var lines: [String] = [
            "Skill: \(skill.name)",
            "Skill key: \(skill.skillKey)",
            "Scope: \(skill.scope)",
            "Canonical path: \(skill.canonicalSourcePath)",
            "Issue (\(issue.code)): \(issue.message)"
        ]

        if let source = issue.source {
            if let line = issue.line {
                lines.append("Issue source: \(source):\(line)")
            } else {
                lines.append("Issue source: \(source)")
            }
        }
        if !issue.details.isEmpty {
            lines.append("Issue details: \(issue.details)")
        }

        if let workspace = skill.workspace, !workspace.isEmpty {
            lines.append("Workspace: \(workspace)")
        }

        lines.append("")
        lines.append("Please investigate and repair this skill package.")
        lines.append("Check SKILL.md availability, symlinks, and referenced files. Then fix the root cause.")

        return lines.joined(separator: "\n")
    }
}
