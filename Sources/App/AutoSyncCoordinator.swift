import Darwin
import Foundation

enum AutoSyncEvent {
    case skillsFilesystemChanged
    case workspaceWatchListChanged
    case runtimeStateChanged
}

protocol AutoSyncCoordinating: AnyObject {
    func start()
    func stop()
    func refreshWatchedPaths()
}

final class AutoSyncCoordinator: AutoSyncCoordinating {
    private struct WatchHandle {
        let source: DispatchSourceFileSystemObject
    }

    private let environment: SyncEngineEnvironment
    private let preferencesStore: SyncPreferencesStore
    private let fileManager: FileManager
    private let queue: DispatchQueue
    private let discoveryInterval: TimeInterval
    private let onEvent: (AutoSyncEvent) -> Void
    private let maxCustomDiscoveryDepth = 3

    private var watchers: [String: WatchHandle] = [:]
    private var discoveryTimer: DispatchSourceTimer?
    private var isRunning = false
    private var knownWorkspacePaths: Set<String> = []

    init(
        environment: SyncEngineEnvironment = .current,
        preferencesStore: SyncPreferencesStore = SyncPreferencesStore(),
        fileManager: FileManager = .default,
        queue: DispatchQueue = DispatchQueue(label: "SkillsSync.AutoSyncCoordinator"),
        discoveryInterval: TimeInterval = 30,
        onEvent: @escaping (AutoSyncEvent) -> Void
    ) {
        self.environment = environment
        self.preferencesStore = preferencesStore
        self.fileManager = fileManager
        self.queue = queue
        self.discoveryInterval = discoveryInterval
        self.onEvent = onEvent
    }

    func start() {
        guard !isRunning else {
            return
        }
        isRunning = true
        try? fileManager.createDirectory(at: runtimeDirectory(), withIntermediateDirectories: true)
        rebuildWatchers(notifyWorkspaceChanges: false)
        startDiscoveryTimer()
    }

    func stop() {
        guard isRunning else {
            return
        }
        isRunning = false
        discoveryTimer?.cancel()
        discoveryTimer = nil
        teardownAllWatchers()
        knownWorkspacePaths = []
    }

    func refreshWatchedPaths() {
        guard isRunning else {
            return
        }
        rebuildWatchers(notifyWorkspaceChanges: true)
    }

    private func startDiscoveryTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + discoveryInterval, repeating: discoveryInterval)
        timer.setEventHandler { [weak self] in
            self?.rebuildWatchers(notifyWorkspaceChanges: true)
        }
        timer.resume()
        discoveryTimer = timer
    }

    private func rebuildWatchers(notifyWorkspaceChanges: Bool) {
        let workspacePaths = Set(discoverWorkspaceCandidates().map(\.path))
        if notifyWorkspaceChanges, workspacePaths != knownWorkspacePaths {
            onEvent(.workspaceWatchListChanged)
        }
        knownWorkspacePaths = workspacePaths

        let watchPlan = buildWatchPlan(workspacePaths: workspacePaths)
        let desiredPaths = Set(watchPlan.map(\.path))
        let currentPaths = Set(watchers.keys)

        for removed in currentPaths.subtracting(desiredPaths) {
            removeWatcher(forPath: removed)
        }

        for item in watchPlan where watchers[item.path] == nil {
            addWatcher(path: item.path, event: item.event)
        }
    }

    private func buildWatchPlan(workspacePaths: Set<String>) -> [(path: String, event: AutoSyncEvent)] {
        var paths: [(String, AutoSyncEvent)] = [
            (claudeGlobalRoot().path, .skillsFilesystemChanged),
            (agentsGlobalRoot().path, .skillsFilesystemChanged),
            (codexGlobalRoot().path, .skillsFilesystemChanged),
            (runtimeDirectory().path, .runtimeStateChanged)
        ]

        for workspacePath in workspacePaths.sorted() {
            let workspace = URL(fileURLWithPath: workspacePath, isDirectory: true)
            paths.append((workspace.appendingPathComponent(".claude/skills", isDirectory: true).path, .skillsFilesystemChanged))
            paths.append((workspace.appendingPathComponent(".agents/skills", isDirectory: true).path, .skillsFilesystemChanged))
            paths.append((workspace.appendingPathComponent(".codex/skills", isDirectory: true).path, .skillsFilesystemChanged))
        }

        return paths
    }

    private func addWatcher(path: String, event: AutoSyncEvent) {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return
        }

        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else {
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete, .attrib, .extend, .link, .revoke],
            queue: queue
        )

        source.setEventHandler { [weak self] in
            self?.onEvent(event)
        }
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()

        watchers[path] = WatchHandle(source: source)
    }

    private func removeWatcher(forPath path: String) {
        guard let handle = watchers.removeValue(forKey: path) else {
            return
        }
        handle.source.cancel()
    }

    private func teardownAllWatchers() {
        let all = watchers.values
        watchers.removeAll()
        for handle in all {
            handle.source.cancel()
        }
    }

    private func discoverWorkspaceCandidates() -> [URL] {
        var candidates: [URL] = []

        if let devRepos = try? fileManager.contentsOfDirectory(
            at: environment.devRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for repo in devRepos where hasWorkspaceSkills(repo) {
                candidates.append(repo)
            }
        }

        if let owners = try? fileManager.contentsOfDirectory(
            at: environment.worktreesRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for owner in owners {
                guard let repos = try? fileManager.contentsOfDirectory(
                    at: owner,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                ) else {
                    continue
                }
                for repo in repos where hasWorkspaceSkills(repo) {
                    candidates.append(repo)
                }
            }
        }

        for root in customWorkspaceDiscoveryRoots() {
            candidates.append(contentsOf: discoverWorkspaces(in: root, depth: 0))
        }

        let uniqueByPath = Dictionary(uniqueKeysWithValues: candidates.map { ($0.standardizedFileURL.path, $0) })
        return uniqueByPath.values.sorted { $0.path < $1.path }
    }

    private func customWorkspaceDiscoveryRoots() -> [URL] {
        let configured = preferencesStore.loadSettings().workspaceDiscoveryRoots
        var roots: [URL] = []
        var seen: Set<String> = []

        for raw in configured {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.hasPrefix("/") else {
                continue
            }
            let normalized = URL(fileURLWithPath: trimmed, isDirectory: true).standardizedFileURL
            let key = normalized.path
            guard !seen.contains(key) else {
                continue
            }
            seen.insert(key)
            roots.append(normalized)
        }

        return roots
    }

    private func discoverWorkspaces(in root: URL, depth: Int) -> [URL] {
        guard fileManager.fileExists(atPath: root.path) else {
            return []
        }

        var result: [URL] = []
        if hasWorkspaceSkills(root) {
            result.append(root)
        }

        guard depth < maxCustomDiscoveryDepth else {
            return result
        }

        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let children = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            return result
        }

        for child in children {
            let values = try? child.resourceValues(forKeys: Set(keys))
            guard values?.isDirectory == true else {
                continue
            }
            if values?.isSymbolicLink == true {
                continue
            }
            result.append(contentsOf: discoverWorkspaces(in: child, depth: depth + 1))
        }

        return result
    }

    private func hasWorkspaceSkills(_ repo: URL) -> Bool {
        let claude = repo.appendingPathComponent(".claude/skills", isDirectory: true)
        let agents = repo.appendingPathComponent(".agents/skills", isDirectory: true)
        let codex = repo.appendingPathComponent(".codex/skills", isDirectory: true)
        return fileManager.fileExists(atPath: claude.path)
            || fileManager.fileExists(atPath: agents.path)
            || fileManager.fileExists(atPath: codex.path)
    }

    private func claudeGlobalRoot() -> URL {
        environment.homeDirectory.appendingPathComponent(".claude/skills", isDirectory: true)
    }

    private func agentsGlobalRoot() -> URL {
        environment.homeDirectory.appendingPathComponent(".agents/skills", isDirectory: true)
    }

    private func codexGlobalRoot() -> URL {
        environment.homeDirectory.appendingPathComponent(".codex/skills", isDirectory: true)
    }

    private func runtimeDirectory() -> URL {
        environment.runtimeDirectory
    }
}
