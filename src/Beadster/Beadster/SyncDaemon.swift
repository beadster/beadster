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
class SyncDaemon: ObservableObject, FileSyncDelegate {
    static let shared = SyncDaemon()

    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var syncError: String?
    @Published var currentSyncingIssueId: String?
    @Published var lastLocalChangeDate: Date?
    @Published var watchedProjectsCount: Int = 0

    private var fileWatcher: ProjectFileWatcher!
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

        // initialize file watcher with self as delegate
        fileWatcher = ProjectFileWatcher(syncDelegate: self)

        // observe file watcher's count changes
        Task { @MainActor in
            for await count in fileWatcher.$watchedProjectsCount.values {
                self.watchedProjectsCount = count
                print("📊 SyncDaemon: watched projects count updated to \(count)")
            }
        }
    }

    // MARK: - Start/Stop

    func start() {
        print("Starting sync daemon...")
        print("Cloud sync enabled: \(AppConfig.cloudSyncEnabled)")

        // File watching is always enabled (for local mode)
        // Cloud sync only happens if cloudSyncEnabled = true

        if AppConfig.cloudSyncEnabled {
            // trigger initial cloud sync
            Task { @MainActor in
                await syncAll()
            }

            // start periodic cloud sync
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

    // MARK: - File Watching (delegated to FileWatcher)

    nonisolated func startWatching(project: ProjectInfo) {
        Task { @MainActor in
            fileWatcher.startWatching(project: project)
        }
    }

    func stopWatching(projectId: String) {
        fileWatcher.stopWatching(projectId: projectId)
    }

    func stopAllWatchers() {
        fileWatcher.stopAllWatchers()
    }

    // FileSyncDelegate implementation
    func onFileChanged(project: ProjectInfo) async {
        lastLocalChangeDate = Date()

        // Only sync to cloud if cloud mode is enabled
        if AppConfig.cloudSyncEnabled {
            await syncProject(project)
        } else {
            print("File changed in \(project.name) - cloud sync disabled (local-only mode)")
        }
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
            let gitInfo = GitInfoReader.readGitInfo(at: latestProject.path)

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
            SyncNotifications.send(title: "Sync Complete", body: "Successfully synced \(latestProject.name)")

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
                SyncNotifications.send(
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

        // Delegate to SyncPullHandler
        _ = try await SyncPullHandler.pullAndApply(
            projectURL: projectURL,
            sourceId: sourceId,
            since: since
        )
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

