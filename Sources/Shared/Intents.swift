import AppIntents

struct SyncNowIntent: AppIntent {
    static let title: LocalizedStringResource = "Sync skills now"
    static let description = IntentDescription("Run an immediate skills sync.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        let engine = SyncEngine()
        _ = try await engine.runSync(trigger: .widget)
        return .result()
    }
}
