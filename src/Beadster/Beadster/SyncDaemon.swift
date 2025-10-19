//
//  SyncDaemon.swift
//  Beadster
//
//  Created by Anton Podviaznikov on 10/18/25.
//

import Foundation

import Dispatch
import UserNotifications

@MainActor
class SyncDaemon: ObservableObject {
    static let shared = SyncDaemon()

    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var syncError: String?
    @Published var currentSyncingIssueId: String?
    @Published var watchedProjectsCount: Int = 0
    @Published var lastLocalChangeDate: Date?

    private var watchers: [String: DispatchSourceFileSystemObject] = [:]
    private var syncTimer: Timer?
    private let syncInterval: TimeInterval = 60 // 1 minute
    private var lastSync: [String: Date] = [:] // project id -> last sync time
    private var retryQueue: [(project: ProjectInfo, retryCount: Int, nextRetry: Date)] = []
    private var retryTimer: Timer?
    private let maxRetries = 3
    private let baseRetryDelay: TimeInterval = 30 // 30 seconds

    // device ID for tracking
    private let deviceId: String

    // reference to ProjectStore to get latest project data
    weak var projectStore: ProjectStore?

    private init() {
        // get hardware-based device ID
        deviceId = DeviceID.shared.getDeviceId()
        print("SyncDaemon initialized with device ID: \(deviceId)")
    }

    // MARK: - Start/Stop

    func start() {
        print("Starting sync daemon...")

        // trigger initial sync
        Task { @MainActor in
            await syncAll()
        }

        // start periodic sync
        syncTimer = Timer.scheduledTimer(withTimeInterval: syncInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.syncAll()
            }
        }

        // start retry timer (check every 10 seconds)
        retryTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.processRetryQueue()
            }
        }
    }

    func stop() {
        print("Stopping sync daemon...")

        // stop timers
        syncTimer?.invalidate()
        syncTimer = nil
        retryTimer?.invalidate()
        retryTimer = nil

        // stop all watchers
        stopAllWatchers()
    }

    // MARK: - File Watching

    nonisolated func startWatching(project: ProjectInfo) {
        // resolve bookmark
        var isStale = false
        guard let projectURL = try? URL(
            resolvingBookmarkData: project.bookmark,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            print("Failed to resolve bookmark for \(project.name)")
            return
        }

        // access security scoped resource
        guard projectURL.startAccessingSecurityScopedResource() else {
            print("Failed to access \(projectURL)")
            return
        }

        // find actual database file (bd names it after project)
        guard let dbFile = BeadsHelper.findDatabaseFile(in: projectURL) else {
            projectURL.stopAccessingSecurityScopedResource()
            print("No beads database found for \(project.name)")
            return
        }

        guard FileManager.default.fileExists(atPath: dbFile.path) else {
            projectURL.stopAccessingSecurityScopedResource()
            print("Beads database file not accessible for \(project.name)")
            return
        }

        // open file descriptor
        let fd = open(dbFile.path, O_EVTONLY)
        guard fd >= 0 else {
            projectURL.stopAccessingSecurityScopedResource()
            print("Failed to open \(dbFile.path)")
            return
        }

        // create dispatch source
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: DispatchQueue.global()
        )

        source.setEventHandler { [weak self] in
            print("File changed: \(dbFile.path)")
            Task { @MainActor in
                self?.lastLocalChangeDate = Date()
                await self?.syncProject(project)
            }
        }

        source.setCancelHandler {
            close(fd)
            projectURL.stopAccessingSecurityScopedResource()
        }

        source.resume()

        Task { @MainActor [weak self] in
            self?.watchers[project.id] = source
            self?.watchedProjectsCount = (self?.watchers.count ?? 0)
            print("Started watching: \(dbFile.path)")
        }
    }

    func stopWatching(projectId: String) {
        watchers[projectId]?.cancel()
        watchers.removeValue(forKey: projectId)
        watchedProjectsCount = watchers.count
    }

    func stopAllWatchers() {
        for (_, watcher) in watchers {
            watcher.cancel()
        }
        watchers.removeAll()
        watchedProjectsCount = 0
    }

    // MARK: - Sync

    func syncAll() async {
        print("Syncing all projects...")
        guard let projectStore = projectStore else {
            print("No project store reference")
            return
        }

        for project in projectStore.projects {
            guard project.sourceId != nil else {
                print("Skipping \(project.name) - no source ID")
                continue
            }
            await syncProject(project)
        }
    }

    func syncProject(_ project: ProjectInfo, retryCount: Int = 0) async {
        guard !isSyncing else {
            print("Sync already in progress")
            return
        }

        // get latest project data from store (sourceId might have been updated)
        guard let latestProject = projectStore?.projects.first(where: { $0.id == project.id }) else {
            print("Project not found in store: \(project.name)")
            return
        }

        isSyncing = true
        defer { isSyncing = false }

        if retryCount > 0 {
            print("🔁 Retry \(retryCount)/\(maxRetries) for \(latestProject.name)")
        } else {
            print("Syncing project: \(latestProject.name)")
        }

        do {
            // resolve bookmark
            var isStale = false
            guard let projectURL = try? URL(
                resolvingBookmarkData: latestProject.bookmark,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else {
                throw SyncError.bookmarkFailed
            }

            // access security scoped resource
            guard projectURL.startAccessingSecurityScopedResource() else {
                throw SyncError.accessDenied
            }
            defer { projectURL.stopAccessingSecurityScopedResource() }

            // 1. Read local issues from SQLite
            let db = BeadsDatabase(beadsDir: projectURL)
            try db.open()
            defer { db.close() }

            let localIssues = try db.getAllIssues()
            print("Found \(localIssues.count) local issues")

            // 2. Get or create source on cloud
            guard let sourceId = latestProject.sourceId else {
                print("No source ID - skipping cloud sync for now")
                lastSyncDate = Date()
                syncError = nil
                return
            }

            // 3. Capture git context for the project
            let gitInfo = latestProject.path.map { GitInfoReader.readGitInfo(at: $0) } ?? nil

            // 4. Push local changes to cloud with git context
            let sourcePayload = SourcePayload(
                id: sourceId,
                name: latestProject.name,
                type: "local",
                path: latestProject.path,
                gitRepoUrl: gitInfo?.repoUrl,
                gitCurrentBranch: gitInfo?.currentBranch
            )

            // Enrich issues with git context
            let issuesWithGit = localIssues.map { issue in
                var enrichedIssue = issue
                enrichedIssue.gitRepoUrl = gitInfo?.repoUrl
                enrichedIssue.gitBranch = gitInfo?.currentBranch
                enrichedIssue.gitCommitHash = gitInfo?.commitHash
                enrichedIssue.gitIsDirty = gitInfo?.isDirty
                return enrichedIssue
            }

            try await APIClient.shared.pushIssues(source: sourcePayload, issues: issuesWithGit)
            print("⬆️  Pushed \(issuesWithGit.count) issue(s) to cloud with git context")

            // 5. Pull remote changes and apply locally
            try await pullAndApplyChanges(project: latestProject, projectURL: projectURL, sourceId: sourceId)

            // 6. Record device tracking for all synced issues
            try await recordDeviceTracking(sourceId: sourceId, issues: issuesWithGit)

            lastSync[latestProject.id] = Date()
            lastSyncDate = Date()
            syncError = nil

            print("✅ Sync completed successfully")

            // send success notification
            sendNotification(title: "Sync Complete", body: "Successfully synced \(latestProject.name)")

        } catch {
            print("❌ Sync failed: \(error)")

            // classify error
            if isRetriableError(error) && retryCount < maxRetries {
                let delay = exponentialBackoff(retryCount: retryCount)
                print("⏳ Will retry in \(Int(delay))s (attempt \(retryCount + 1)/\(maxRetries))")
                addToRetryQueue(latestProject, retryCount: retryCount + 1, delay: delay)
                syncError = "Sync failed, retrying in \(Int(delay))s: \(friendlyErrorMessage(error))"
            } else {
                let message = retryCount > 0 ? "after \(retryCount) retries" : ""
                syncError = "Sync failed \(message): \(friendlyErrorMessage(error))"
                print("🛑 Max retries reached or non-retriable error")

                // send error notification
                sendNotification(
                    title: "Sync Failed",
                    body: "Failed to sync \(latestProject.name): \(friendlyErrorMessage(error))"
                )
            }
        }
    }

    // MARK: - Retry Logic

    private func isRetriableError(_ error: Error) -> Bool {
        // network errors are retriable
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost, .cannotFindHost:
                return true
            default:
                return false
            }
        }

        // API errors 5xx are retriable
        if let syncError = error as? SyncError {
            switch syncError {
            case .networkError:
                return true
            default:
                return false
            }
        }

        return false
    }

    private func exponentialBackoff(retryCount: Int) -> TimeInterval {
        // 30s, 60s, 120s
        return baseRetryDelay * pow(2.0, Double(retryCount))
    }

    private func friendlyErrorMessage(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet:
                return "No internet connection"
            case .networkConnectionLost:
                return "Network connection lost"
            case .timedOut:
                return "Request timed out"
            case .cannotConnectToHost, .cannotFindHost:
                return "Cannot reach server"
            default:
                return urlError.localizedDescription
            }
        }

        return error.localizedDescription
    }

    private func addToRetryQueue(_ project: ProjectInfo, retryCount: Int, delay: TimeInterval) {
        let nextRetry = Date().addingTimeInterval(delay)

        // remove existing entry for this project
        retryQueue.removeAll { $0.project.id == project.id }

        // add new entry
        retryQueue.append((project: project, retryCount: retryCount, nextRetry: nextRetry))

        print("📋 Added \(project.name) to retry queue (retry at \(nextRetry.formatted(.dateTime.hour().minute().second())))")
    }

    private func processRetryQueue() async {
        guard !isSyncing else { return }

        let now = Date()
        let readyToRetry = retryQueue.filter { $0.nextRetry <= now }

        guard !readyToRetry.isEmpty else { return }

        print("🔄 Processing retry queue (\(readyToRetry.count) ready)")

        // remove from queue
        let entry = readyToRetry.first!
        retryQueue.removeAll { $0.project.id == entry.project.id }

        // retry sync
        await syncProject(entry.project, retryCount: entry.retryCount)
    }

    func manualSync(project: ProjectInfo) async {
        await syncProject(project)
    }

    // MARK: - Pull & Apply Changes

    private func pullAndApplyChanges(project: ProjectInfo, projectURL: URL, sourceId: String) async throws {
        // Get timestamp of last sync for this project
        let since = Int(lastSync[project.id]?.timeIntervalSince1970 ?? 0)

        print("🔽 Pulling changes since \(since)...")

        // Get remote changes
        let changes = try await APIClient.shared.pullChanges(sourceId: sourceId, since: since)

        if changes.isEmpty {
            print("  ✓ No changes from cloud")
            return
        }

        print("⬇️  Applying \(changes.count) change(s)...")

        // Open database to check which issues exist locally
        let db = BeadsDatabase(beadsDir: projectURL)
        try db.open()
        defer { db.close() }

        // Apply each change via bd CLI
        for issue in changes {
            // Check if issue exists locally
            let existsLocally = try db.issueExists(beadsId: issue.id)

            // Only update existing issues
            // Skip creating new issues from cloud (would create ID mismatch)
            guard existsLocally else {
                print("  ⊘ Skipping new issue from cloud: \(issue.title) (id=\(issue.id))")
                continue
            }

            // Apply change via bd update command
            try await applyChange(issue: issue, projectPath: projectURL.path)
        }

        print("  ✅ Applied \(changes.count) change(s)")
    }

    private func applyChange(issue: Issue, projectPath: String) async throws {
        // Escape title for shell command
        let escapedTitle = issue.title.replacingOccurrences(of: "\"", with: "\\\"")

        // Build bd update command
        let command = """
        cd "\(projectPath)" && bd update \(issue.id) \
        --title="\(escapedTitle)" \
        --status=\(issue.status) \
        --priority=\(issue.priority)
        """

        print("  🔄 Updating: \(issue.title)")

        // Execute command
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]

        // Capture output
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            print("  ❌ Failed to update \(issue.id): \(errorOutput)")
            throw SyncError.bdCommandFailed(errorOutput)
        }

        print("  ✓ Updated: \(issue.title)")
    }

    // MARK: - Merge Logic

    func mergeIssues(local: [Issue], remote: [Issue]) -> [Issue] {
        // POC: last write wins
        var merged: [String: Issue] = [:]

        // add all local issues
        for issue in local {
            merged[issue.id] = issue
        }

        // override with remote if remote is newer
        for remoteIssue in remote {
            if let localIssue = merged[remoteIssue.id] {
                // compare timestamps
                if remoteIssue.updatedAt > localIssue.updatedAt {
                    merged[remoteIssue.id] = remoteIssue
                }
            } else {
                // new remote issue
                merged[remoteIssue.id] = remoteIssue
            }
        }

        return Array(merged.values)
    }

    // MARK: - Device Tracking

    private func recordDeviceTracking(sourceId: String, issues: [Issue]) async throws {
        print("📍 Recording device tracking for \(issues.count) issues...")

        // Get device ID (should be set during app initialization)
        guard let deviceId = UserDefaults.standard.string(forKey: "beadster_device_id") else {
            print("⚠️  No device ID - skipping device tracking")
            return
        }

        // Record tracking for each issue
        for issue in issues {
            do {
                try await APIClient.shared.recordDeviceTracking(
                    issueId: issue.id,
                    deviceId: deviceId,
                    client: "macos"
                )
            } catch {
                // Don't fail sync if tracking fails
                print("⚠️  Failed to record tracking for \(issue.id): \(error)")
            }
        }

        print("  ✓ Device tracking recorded")
    }

    // MARK: - Notifications

    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // immediate
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to send notification: \(error)")
            }
        }
    }
}

// MARK: - Errors

enum SyncError: LocalizedError {
    case bookmarkFailed
    case accessDenied
    case networkError
    case mergeConflict
    case bdCommandFailed(String)

    var errorDescription: String? {
        switch self {
        case .bookmarkFailed: return "Failed to resolve project bookmark"
        case .accessDenied: return "Access denied to project folder"
        case .networkError: return "Network error during sync"
        case .mergeConflict: return "Merge conflict detected"
        case .bdCommandFailed(let error): return "bd command failed: \(error)"
        }
    }
}
