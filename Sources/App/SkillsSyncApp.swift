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
                        viewModel.selectedSkillIDs = Set([skillID])
                    }
                }
                .alert("Operation Failed", isPresented: Binding(
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

    private var syncErrorBanner: InlineBannerPresentation? {
        let hasError = !(viewModel.state.sync.error?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        guard viewModel.state.sync.status == .failed || hasError else {
            return nil
        }
        return .syncFailure(errorDetails: viewModel.state.sync.error)
    }

    private var feedbackMessages: [InlineBannerPresentation] {
        [syncErrorBanner, viewModel.localBanner].compactMap { $0 }
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(
                skills: viewModel.filteredSkills,
                searchText: $viewModel.searchText,
                scopeFilter: $viewModel.scopeFilter,
                selectedSkillIDs: $viewModel.selectedSkillIDs
            )
            .navigationSplitViewColumnWidth(min: 300, ideal: 340, max: 420)
        } detail: {
            DetailPaneView(
                state: viewModel.state,
                selectedSkills: viewModel.selectedSkills,
                singleSelectedSkill: viewModel.singleSelectedSkill,
                feedbackMessages: feedbackMessages,
                onSyncNow: viewModel.syncNow,
                onOpen: viewModel.open,
                onReveal: viewModel.reveal,
                onDelete: viewModel.delete,
                onDeleteSelected: viewModel.deleteSelectedSkills
            )
        }
        .toolbar {
            ToolbarItemGroup {
                Button("Refresh") {
                    viewModel.refreshSources()
                }
                Button("Sync Now") {
                    viewModel.syncNow()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
    }
}

private struct SidebarView: View {
    let skills: [SkillRecord]
    @Binding var searchText: String
    @Binding var scopeFilter: ScopeFilter
    @Binding var selectedSkillIDs: Set<String>

    var body: some View {
        VStack(spacing: 8) {
            Picker("Scope", selection: $scopeFilter) {
                ForEach(ScopeFilter.allCases) { scope in
                    Text(scope.title).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 8)
            .padding(.top, 8)

            if skills.isEmpty {
                ContentUnavailableView {
                    Label("No Skills Found", systemImage: "tray")
                } description: {
                    Text("Run Sync Now to discover skills, then select one to inspect.")
                }
            } else {
                List(selection: $selectedSkillIDs) {
                    Section("Source Skills (\(skills.count))") {
                        ForEach(skills, id: \.id) { skill in
                            SkillRowView(skill: skill)
                                .tag(skill.id)
                        }
                    }
                }
                .listStyle(.sidebar)
                .searchable(text: $searchText, placement: .sidebar, prompt: "Search skills and paths")
            }
        }
    }
}

private struct SkillRowView: View {
    let skill: SkillRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(skill.name)
                .font(.body.weight(.semibold))
                .lineLimit(1)

            Text(skill.canonicalSourcePath)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            if !skill.exists {
                Label("Missing source", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(skill.accessibilitySummary)
    }
}

private struct DetailPaneView: View {
    let state: SyncState
    let selectedSkills: [SkillRecord]
    let singleSelectedSkill: SkillRecord?
    let feedbackMessages: [InlineBannerPresentation]
    let onSyncNow: () -> Void
    let onOpen: (SkillRecord) -> Void
    let onReveal: (SkillRecord) -> Void
    let onDelete: (SkillRecord) -> Void
    let onDeleteSelected: () -> Void

    var body: some View {
        if let singleSelectedSkill {
            SkillDetailView(
                state: state,
                skill: singleSelectedSkill,
                feedbackMessages: feedbackMessages,
                onSyncNow: onSyncNow,
                onOpen: onOpen,
                onReveal: onReveal,
                onDelete: onDelete
            )
        } else if selectedSkills.count > 1 {
            MultiSelectionDetailView(
                state: state,
                selectedCount: selectedSkills.count,
                feedbackMessages: feedbackMessages,
                onSyncNow: onSyncNow,
                onDeleteSelected: onDeleteSelected
            )
        } else {
            VStack(spacing: 0) {
                HomeSyncHealthView(
                    state: state,
                    feedbackMessages: feedbackMessages,
                    onSyncNow: onSyncNow
                )
                ContentUnavailableView {
                    Label("Choose a Skill", systemImage: "sidebar.right")
                } description: {
                    Text("Select a skill from the sidebar to inspect details and run actions.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

private struct HomeSyncHealthView: View {
    let state: SyncState
    let feedbackMessages: [InlineBannerPresentation]
    let onSyncNow: () -> Void

    private var status: SyncStatusPresentation {
        state.sync.status.presentation
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label(status.title, systemImage: status.symbol)
                    .foregroundStyle(status.tint)
                    .font(.headline)

                VStack(alignment: .leading, spacing: 6) {
                    HomeMetricRow(label: "Last update", value: SyncFormatting.updatedLine(state.sync.lastFinishedAt))
                    HomeMetricRow(label: "Global", value: "\(state.summary.globalCount)")
                    HomeMetricRow(label: "Project", value: "\(state.summary.projectCount)")
                    HomeMetricRow(label: "Conflicts", value: "\(state.summary.conflictCount)")
                }

                if !status.subtitle.isEmpty {
                    Text(status.subtitle)
                        .foregroundStyle(.secondary)
                }

                ForEach(Array(feedbackMessages.enumerated()), id: \.offset) { _, message in
                    VStack(alignment: .leading, spacing: 2) {
                        Label(message.title, systemImage: message.symbol)
                            .foregroundStyle(message.role.tint)
                        Text(message.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if feedbackMessages.contains(where: { $0.recoveryActionTitle != nil }) {
                    Button("Sync Now") {
                        onSyncNow()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text("Sync Health")
        }
        .padding(12)
    }
}

private struct HomeMetricRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct MultiSelectionDetailView: View {
    let state: SyncState
    let selectedCount: Int
    let feedbackMessages: [InlineBannerPresentation]
    let onSyncNow: () -> Void
    let onDeleteSelected: () -> Void
    @State private var showDeleteConfirmation = false

    var body: some View {
        Form {
            SyncStatusSection(state: state, feedbackMessages: feedbackMessages, onSyncNow: onSyncNow)

            Section("Selection") {
                LabeledContent("Selected", value: "\(selectedCount)")
                Text("Selected: \(selectedCount)")
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Move Selected Sources to Trash", role: .destructive) {
                    showDeleteConfirmation = true
                }
                .accessibilityLabel("Move \(selectedCount) selected sources to Trash")
            } header: {
                Text("Danger Zone")
            } footer: {
                Text("This moves canonical sources to Trash. Some items may fail; successful deletions will still be applied.")
            }
        }
        .confirmationDialog(
            "Move \(selectedCount) sources to Trash?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                onDeleteSelected()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Selected canonical sources will be moved to Trash in a batch operation.")
        }
        .formStyle(.grouped)
    }
}

private struct SkillDetailView: View {
    let state: SyncState
    let skill: SkillRecord
    let feedbackMessages: [InlineBannerPresentation]
    let onSyncNow: () -> Void
    let onOpen: (SkillRecord) -> Void
    let onReveal: (SkillRecord) -> Void
    let onDelete: (SkillRecord) -> Void
    @State private var showDeleteConfirmation = false

    var body: some View {
        Form {
            SyncStatusSection(state: state, feedbackMessages: feedbackMessages, onSyncNow: onSyncNow)

            Section("Overview") {
                LabeledContent("Name", value: skill.name)
                LabeledContent("Source status", value: skill.exists ? "Available" : "Missing")
                LabeledContent("Package type", value: skill.packageType)
                LabeledContent("Scope", value: skill.scopeTitle)
                if let workspace = skill.workspace {
                    LabeledContent("Workspace") {
                        Text(workspace)
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                            .multilineTextAlignment(.leading)
                            .lineLimit(nil)
                    }
                }
            }

            Section("Paths") {
                PathLine(label: "Source path", value: skill.canonicalSourcePath)
                ForEach(Array(skill.targetPaths.enumerated()), id: \.offset) { index, path in
                    PathLine(label: "Target \(index + 1)", value: path)
                }
            }

            Section("Integrity") {
                LabeledContent("Source file", value: skill.exists ? "Available" : "Missing from disk")
                LabeledContent("Canonical symlink", value: skill.isSymlinkCanonical ? "Yes" : "No")
            }

            Section("Actions") {
                ControlGroup {
                    Button("Open in Zed") {
                        onOpen(skill)
                    }
                    Button("Reveal in Finder") {
                        onReveal(skill)
                    }
                }
            }

            Section {
                Button("Move Source to Trash", role: .destructive) {
                    showDeleteConfirmation = true
                }
            } header: {
                Text("Danger Zone")
            } footer: {
                Text("This moves the canonical source to Trash. You can restore it or run sync again to recreate it.")
            }
        }
        .confirmationDialog(
            "Move Source to Trash?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                onDelete(skill)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The canonical source will be moved to Trash.")
        }
        .formStyle(.grouped)
    }
}

private struct SyncStatusSection: View {
    let state: SyncState
    let feedbackMessages: [InlineBannerPresentation]
    let onSyncNow: () -> Void

    private var status: SyncStatusPresentation {
        state.sync.status.presentation
    }

    var body: some View {
        Section("Sync Health") {
            LabeledContent("Status") {
                Label(status.title, systemImage: status.symbol)
                    .foregroundStyle(status.tint)
            }
            LabeledContent("Last update", value: SyncFormatting.updatedLine(state.sync.lastFinishedAt))
            LabeledContent("Global", value: "\(state.summary.globalCount)")
            LabeledContent("Project", value: "\(state.summary.projectCount)")
            LabeledContent("Conflicts", value: "\(state.summary.conflictCount)")

            if !status.subtitle.isEmpty {
                Text(status.subtitle)
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(feedbackMessages.enumerated()), id: \.offset) { _, message in
                VStack(alignment: .leading, spacing: 2) {
                    Label(message.title, systemImage: message.symbol)
                        .foregroundStyle(message.role.tint)
                    Text(message.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if feedbackMessages.contains(where: { $0.recoveryActionTitle != nil }) {
                Button("Sync Now") {
                    onSyncNow()
                }
            }
        }
    }
}

private struct PathLine: View {
    let label: String
    let value: String

    var body: some View {
        LabeledContent(label) {
            Text(value)
                .font(.footnote.monospaced())
                .lineLimit(nil)
                .multilineTextAlignment(.leading)
                .textSelection(.enabled)
        }
    }
}

private extension SkillRecord {
    var scopeTitle: String {
        scope.capitalized
    }

    var accessibilitySummary: String {
        var summary = "\(name)."
        if !exists {
            summary += " Source missing."
        }
        return summary
    }
}
