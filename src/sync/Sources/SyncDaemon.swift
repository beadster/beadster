import Foundation

class SyncDaemon {
    private let config: Config
    private var watchers: [FileWatcher] = []
    private var lastSync: [String: Int] = [:] // source path -> timestamp
    private let sessionTracker = SessionTracker()

    init(configPath: String) throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: configPath))
        self.config = try JSONDecoder().decode(Config.self, from: data)
    }

    func start() async {
        print("🚀 Beadster sync daemon starting...")

        // Initial sync
        for source in config.sources {
            await syncSource(source)
        }

        // Watch for changes
        for source in config.sources {
            watchSource(source)
        }

        print("👀 Watching \(config.sources.count) source(s)")

        // Pull changes every 10 seconds
        Task {
            while true {
                try await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
                for source in config.sources {
                    await pullChanges(source)
                }
            }
        }

        // Keep running
        RunLoop.main.run()
    }

    func syncSource(_ source: Source) async {
        do {
            let db = BeadsDatabase(beadsDir: source.path)
            try db.open()
            defer { db.close() }

            let issues = try db.getAllIssues()

            // Add session metadata to issues
            let issuesWithSession = issues.map { issue in
                sessionTracker.addSessionLabels(to: issue, beadsDir: source.path)
            }

            let api = CloudAPI(apiUrl: config.apiUrl, apiKey: config.apiKey)
            try await api.pushIssues(source: source, issues: issuesWithSession)

            lastSync[source.path] = Int(Date().timeIntervalSince1970)

            print("✓ Synced \(issuesWithSession.count) issue(s) from \(source.name)")
        } catch DatabaseError.cantOpen {
            print("⚠️  No .beads/ found in \(source.path)")
        } catch {
            print("✗ Sync failed for \(source.name): \(error)")
        }
    }

    func pullChanges(_ source: Source) async {
        do {
            let since = lastSync[source.path] ?? 0

            let api = CloudAPI(apiUrl: config.apiUrl, apiKey: config.apiKey)
            let changes = try await api.pullChanges(source: source, since: since)

            if !changes.isEmpty {
                print("⬇  Pulling \(changes.count) change(s) for \(source.name)")

                // Apply changes via bd CLI
                for issue in changes {
                    try applyChange(source: source, issue: issue)
                }

                lastSync[source.path] = Int(Date().timeIntervalSince1970)
            }
        } catch {
            // Silent fail for pull (not critical)
        }
    }

    func applyChange(source: Source, issue: Issue) throws {
        // Check if issue exists locally
        let db = BeadsDatabase(beadsDir: source.path)
        try db.open()
        defer { db.close() }

        let existsLocally = try db.issueExists(beadsId: issue.beadsId)

        let escapedTitle = issue.title.replacingOccurrences(of: "\"", with: "\\\"")
        let escapedBody = (issue.body ?? "").replacingOccurrences(of: "\"", with: "\\\"")

        let command: String
        if existsLocally {
            // Update existing issue
            command = """
            cd "\(source.path)" && bd update \(issue.beadsId) \
            --title="\(escapedTitle)" \
            --status=\(issue.status) \
            --priority=\(issue.priority ?? "1")
            """
        } else {
            // Create new issue with specific ID
            // Note: bd doesn't support setting custom ID, so we need to use JSONL directly
            command = """
            cd "\(source.path)" && bd create "\(escapedTitle)" \
            --description="\(escapedBody)" \
            --priority=\(issue.priority ?? "1") \
            --status=\(issue.status)
            """
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus == 0 {
            let action = existsLocally ? "Updated" : "Created"
            print("  ✓ \(action): \(issue.title)")
        }
    }

    func watchSource(_ source: Source) {
        let watcher = FileWatcher(path: source.path) { [weak self] in
            guard let self = self else { return }
            print("📝 Change detected in \(source.name)")
            Task {
                await self.syncSource(source)
            }
        }
        watcher.start()
        watchers.append(watcher)
    }
}
