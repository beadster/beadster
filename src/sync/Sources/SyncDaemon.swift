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

        // Pull changes every 10 seconds
        print("⏱  Starting pull loop (every 10s)...")
        Task {
            while true {
                try await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
                print("🔽 Checking for cloud changes...")
                for source in config.sources {
                    await pullChanges(source)
                }
            }
        }

        // Keep running
        print("✅ Daemon running!")
        print("")
        RunLoop.main.run()
    }

    func syncSource(_ source: Source) async {
        do {
            print("    📂 Opening database...")
            let db = BeadsDatabase(beadsDir: source.path)
            try db.open()
            defer { db.close() }

            print("    📊 Reading issues...")
            let issues = try db.getAllIssues()
            print("    📝 Found \(issues.count) issue(s)")

            // Add session metadata to issues
            print("    🏷  Adding session metadata...")
            let issuesWithSession = issues.map { issue in
                sessionTracker.addSessionLabels(to: issue, beadsDir: source.path)
            }

            print("    ⬆️  Pushing to cloud...")
            let api = CloudAPI(apiUrl: config.apiUrl, apiKey: config.apiKey)
            try await api.pushIssues(source: source, issues: issuesWithSession)

            lastSync[source.path] = Int(Date().timeIntervalSince1970)

            print("    ✅ Synced \(issuesWithSession.count) issue(s) from \(source.name)")
        } catch DatabaseError.cantOpen {
            print("    ⚠️  No .beads/ found in \(source.path)")
        } catch {
            print("    ❌ Sync failed for \(source.name): \(error)")
        }
    }

    func pullChanges(_ source: Source) async {
        do {
            let since = lastSync[source.path] ?? 0

            let api = CloudAPI(apiUrl: config.apiUrl, apiKey: config.apiKey)
            let changes = try await api.pullChanges(source: source, since: since)

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
