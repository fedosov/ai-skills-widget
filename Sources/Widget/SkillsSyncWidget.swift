import AppIntents
import SwiftUI
import WidgetKit

struct SkillsWidgetConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Skills sync"
    static let description = IntentDescription("Shows skill sync health and top discovered skills.")
}

struct SkillsWidgetEntry: TimelineEntry {
    let date: Date
    let state: SyncState
    let topSkills: [SkillRecord]
}

struct SkillsWidgetProvider: AppIntentTimelineProvider {
    typealias Entry = SkillsWidgetEntry
    typealias Intent = SkillsWidgetConfigurationIntent

    func recommendations() -> [AppIntentRecommendation<Intent>] {
        [AppIntentRecommendation(intent: .init(), description: "Default")]
    }

    func placeholder(in context: Context) -> SkillsWidgetEntry {
        let state = SyncState.empty
        return SkillsWidgetEntry(date: .now, state: state, topSkills: [])
    }

    func snapshot(for configuration: Intent, in context: Context) async -> SkillsWidgetEntry {
        makeEntry()
    }

    func timeline(for configuration: Intent, in context: Context) async -> Timeline<SkillsWidgetEntry> {
        let entry = makeEntry()
        let next = Date().addingTimeInterval(300)
        return Timeline(entries: [entry], policy: .after(next))
    }

    private func makeEntry() -> SkillsWidgetEntry {
        let store = SyncStateStore()
        let state = store.loadState()
        let topSkills = store.topSkills(from: state)
        return SkillsWidgetEntry(date: .now, state: state, topSkills: topSkills)
    }
}

struct SkillsSyncWidget: Widget {
    let kind = "SkillsSyncWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SkillsWidgetConfigurationIntent.self, provider: SkillsWidgetProvider()) { entry in
            SkillsWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Skills Sync")
        .description("Sync status, conflicts and top skills")
        .supportedFamilies([.systemLarge])
    }
}

struct SkillsWidgetView: View {
    let entry: SkillsWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            HStack(spacing: 8) {
                Button(intent: SyncNowIntent()) {
                    Label("Sync now", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                }
                .buttonStyle(.borderedProminent)

                Link(destination: URL(string: "skillssync://open")!) {
                    Label("Open app", systemImage: "arrow.up.right.square")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }

            Divider()

            if entry.topSkills.isEmpty {
                Text("No discovered skills")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(entry.topSkills.prefix(6), id: \.id) { skill in
                        Link(destination: skill.url) {
                            HStack {
                                Text(skill.name)
                                    .font(.caption)
                                    .lineLimit(1)
                                Spacer()
                                Text(skill.scopeShort)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(12)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle()
                    .fill(entry.state.sync.status.color)
                    .frame(width: 8, height: 8)
                Text(entry.state.sync.status.label)
                    .font(.headline)
                Spacer()
                Text(relativeTime(entry.state.sync.lastFinishedAt))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text("G \(entry.state.summary.globalCount) · P \(entry.state.summary.projectCount) · C \(entry.state.summary.conflictCount)")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if let error = entry.state.sync.error, !error.isEmpty {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
        }
    }

    private func relativeTime(_ iso: String?) -> String {
        guard let iso else { return "never" }
        let parser = ISO8601DateFormatter()
        guard let date = parser.date(from: iso) else { return "unknown" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
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
    var scopeShort: String {
        scope == "global" ? "G" : "P"
    }

    var url: URL {
        URL(string: "skillssync://skill?id=\(id)")!
    }
}

@main
struct SkillsSyncWidgetBundle: WidgetBundle {
    var body: some Widget {
        SkillsSyncWidget()
    }
}
