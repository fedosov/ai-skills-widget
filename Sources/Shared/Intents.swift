import AppIntents
import Foundation
import WidgetKit

struct SyncNowIntent: AppIntent {
    static let title: LocalizedStringResource = "Sync skills now"
    static let description = IntentDescription("Queue an immediate skills sync run.")
    static let openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        let store = SyncStateStore()
        let command = store.makeCommand(type: .syncNow, requestedBy: "widget")
        try store.appendCommand(command)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
