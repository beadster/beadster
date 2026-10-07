import Foundation
import Shared
import FSEventsWatcher

/// CLI-specific sync daemon
/// Reads config from file and syncs sources
class CLISyncDaemon {
    private let config: Config
    private var watchers: [FSEventsWatcher] = []
    private var lastSync: [String: Int] = [:] // source path -> timestamp

    init(configPath: String) throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: configPath))
        self.config = try JSONDecoder().decode(Config.self, from: data)
    }

    func start() async {
        print("🚀 Beadster sync daemon starting...")
        print("📍 API: \(config.apiUrl)")
        print("📁 Sources: \(config.sources.count)")
        print("")

        // Initial sync
        print("🔄 Initial sync...")
        for source in config.sources {
            print("  → Syncing \(source.name) (\(source.path))...")
            await syncSource(source)
        }
        print("")

        // Watch for changes
        print("👁  Setting up file watchers...")
        for source in config.sources {
            watchSource(source)
        }
        print("👀 Watching \(config.sources.count) source(s)")
        print("")

        // Keep running and pull changes every 10 seconds
        print("⏱  Starting pull loop (every 10s)...")
        print("✅ Daemon running!")
        print("")

        while true {
            do {
                try await Task.sleep(nanoseconds: 10_000_000_000)
                print("🔽 Checking for cloud changes...")
                for source in config.sources {
                    await pullChanges(source)
                }
            } catch {
                // Sleep interrupted, continue
            }
        }
    }

    func syncSource(_ source: SourceConfig) async {
        do {
            print("    📂 Opening database...")
            let db = BeadsDatabase(beadsDir: source.path)
            try db.open()
            defer { db.close() }

            print("    📊 Reading issues...")
            let issues = try db.getAllIssues()
            print("    📝 Found \(issues.count) issue(s)")

            print("    ⬆️  Pushing to cloud...")
            let sourceId = generateSourceId(from: source)
            let payload = SourcePayload(
                id: sourceId,
                name: source.name,
                type: "local",
                path: source.path
            )

            try await APIClient.shared.pushIssues(source: payload, issues: issues)

            lastSync[source.path] = Int(Date().timeIntervalSince1970)

            print("    ✅ Synced \(issues.count) issue(s) from \(source.name)")
        } catch DatabaseError.cantOpen {
            print("    ⚠️  No .beads/ found in \(source.path)")
        } catch {
            print("    ❌ Sync failed for \(source.name): \(error)")
        }
    }

    func pullChanges(_ source: SourceConfig) async {
        do {
            let since = lastSync[source.path] ?? 0

            let sourceId = generateSourceId(from: source)
            let changes = try await APIClient.shared.pullChanges(sourceId: sourceId, since: since)

            if !changes.isEmpty {
                print("⬇️  Pulling \(changes.count) change(s) for \(source.name)")

                // Apply changes via bd CLI
                for issue in changes {
                    try applyChange(source: source, issue: issue)
                }

                lastSync[source.path] = Int(Date().timeIntervalSince1970)
            } else {
                print("  ✓ No changes for \(source.name)")
            }
        } catch {
            print("  ⚠️  Pull failed for \(source.name): \(error)")
        }
    }

    func applyChange(source: SourceConfig, issue: Issue) throws {
        // Check if issue exists locally
        let db = BeadsDatabase(beadsDir: source.path)
        try db.open()
        defer { db.close() }

        print("  🔍 Checking issue: beadsId=\(issue.id)")
        let existsLocally = try db.issueExists(beadsId: issue.id)
        print("  🔍 Exists locally: \(existsLocally)")

        // Only sync updates to existing local issues
        guard existsLocally else {
            print("  ⊘ Skipping new issue from cloud: \(issue.title) (beadsId=\(issue.id))")
            return
        }

        let escapedTitle = issue.title.replacingOccurrences(of: "\"", with: "\\\"")

        // Update existing issue
        let command = """
        cd "\(source.path)" && bd update \(issue.id) \
        --title="\(escapedTitle)" \
        --status=\(issue.status) \
        --priority=\(issue.priority)
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus == 0 {
            print("  ✓ Updated: \(issue.title)")
        }
    }

    func watchSource(_ source: SourceConfig) {
        let watcher = FSEventsWatcher(
            paths: [source.path],
            latency: 1.0
        ) { [weak self] events in
            let fileEvents = events.filter { !$0.isHistoryDone }
            guard !fileEvents.isEmpty else { return }
            print("📝 Change detected in \(source.name) (\(fileEvents.count) events)")
            Task { [weak self] in
                await self?.syncSource(source)
            }
        }
        watcher.start()
        watchers.append(watcher)
    }

    private func generateSourceId(from source: SourceConfig) -> String {
        // Simple hash of path for source ID
        return "src-\(source.path.hashValue.magnitude)"
    }
}
