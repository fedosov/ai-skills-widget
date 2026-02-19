import SwiftUI

@main
struct SkillsSyncApp: App {
    @StateObject private var viewModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .frame(minWidth: 980, minHeight: 620)
                .onAppear {
                    viewModel.start()
                }
                .onDisappear {
                    viewModel.stop()
                }
                .onOpenURL { url in
                    guard let route = DeepLinkParser.parse(url) else { return }
                    if case let .skill(id: skillID) = route {
                        viewModel.selectedSkillID = skillID
                    }
                }
                .alert("Operation failed", isPresented: Binding(
                    get: { viewModel.alertMessage != nil },
                    set: { if !$0 { viewModel.alertMessage = nil } }
                )) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text(viewModel.alertMessage ?? "Unknown error")
                }
        }
    }
}

private struct ContentView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 12) {
                statusHeader

                HStack {
                    Button("Sync now") {
                        viewModel.queueSync()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Refresh") {
                        viewModel.load()
                    }
                    .buttonStyle(.bordered)
                }

                TextField("Search skills, scopes, paths", text: $viewModel.searchText)
                    .textFieldStyle(.roundedBorder)

                List(selection: $viewModel.selectedSkillID) {
                    ForEach(viewModel.filteredSkills, id: \.id) { skill in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(skill.name)
                                .font(.headline)
                            Text(skill.scopeLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(skill.canonicalSourcePath)
                                .font(.caption2)
                                .lineLimit(1)
                                .foregroundStyle(.tertiary)
                        }
                        .tag(skill.id)
                    }
                }
            }
            .padding(16)
        } detail: {
            if let selectedSkill = viewModel.state.skills.first(where: { $0.id == viewModel.selectedSkillID }) {
                SkillDetailView(skill: selectedSkill, viewModel: viewModel)
                    .padding(20)
            } else {
                ContentUnavailableView("Select a skill", systemImage: "wrench.and.screwdriver")
            }
        }
    }

    private var statusHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle()
                    .fill(viewModel.state.sync.status.color)
                    .frame(width: 10, height: 10)
                Text(viewModel.state.sync.status.label)
                    .font(.headline)
                Spacer()
                if let finished = viewModel.state.sync.lastFinishedAt {
                    Text(Self.formatRelative(iso: finished))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 16) {
                Text("Global: \(viewModel.state.summary.globalCount)")
                Text("Project: \(viewModel.state.summary.projectCount)")
                Text("Conflicts: \(viewModel.state.summary.conflictCount)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let error = viewModel.state.sync.error, !error.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
    }

    private static func formatRelative(iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: iso) else {
            return iso
        }
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .abbreviated
        return "Updated \(relative.localizedString(for: date, relativeTo: Date()))"
    }
}

private struct SkillDetailView: View {
    let skill: SkillRecord
    @ObservedObject var viewModel: AppViewModel
    @State private var showDeleteConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(skill.name)
                .font(.largeTitle)

            LabeledContent("Scope", value: skill.scopeLabel)
            if let workspace = skill.workspace {
                LabeledContent("Workspace", value: workspace)
            }
            LabeledContent("Source", value: skill.canonicalSourcePath)
            LabeledContent("Target", value: skill.symlinkTarget)
            LabeledContent("Targets count", value: "\(skill.targetPaths.count)")
            LabeledContent("Exists", value: skill.exists ? "yes" : "no")
            LabeledContent("Canonical symlink", value: skill.isSymlinkCanonical ? "yes" : "no")

            Divider()

            HStack {
                Button("Open in Zed") {
                    viewModel.queueOpen(skill: skill)
                }
                .buttonStyle(.borderedProminent)

                Button("Reveal in Finder") {
                    viewModel.queueReveal(skill: skill)
                }
                .buttonStyle(.bordered)

                Button("Delete source") {
                    showDeleteConfirmation = true
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }

            Spacer()
        }
        .confirmationDialog(
            "Delete source skill?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                viewModel.queueDelete(skill: skill)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The canonical source will be moved to Trash. This cannot be triggered silently.")
        }
    }
}

private extension SyncHealthStatus {
    var color: Color {
        switch self {
        case .ok:
            return .green
        case .failed:
            return .red
        case .syncing:
            return .orange
        case .unknown:
            return .gray
        }
    }

    var label: String {
        rawValue.uppercased()
    }
}

private extension SkillRecord {
    var scopeLabel: String {
        if let workspace, !workspace.isEmpty {
            return "\(scope) · \(workspace)"
        }
        return scope
    }
}
