//
//  SyncDaemon.swift
//  Beadster
//
//  Created by Anton Podviaznikov on 10/18/25.
//

import Foundation
import Dispatch

@MainActor
class SyncDaemon: ObservableObject {
    static let shared = SyncDaemon()

    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var syncError: String?

    private var watchers: [String: DispatchSourceFileSystemObject] = [:]
    private var syncTimer: Timer?
    private let syncInterval: TimeInterval = 300 // 5 minutes

    private init() {}

    // MARK: - Start/Stop

    func start() {
        print("Starting sync daemon...")

        // start periodic sync
        syncTimer = Timer.scheduledTimer(withTimeInterval: syncInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.syncAll()
            }
        }
    }

    func stop() {
        print("Stopping sync daemon...")

        // stop timer
        syncTimer?.invalidate()
        syncTimer = nil

        // stop all watchers
        stopAllWatchers()
    }

    // MARK: - File Watching

    func startWatching(project: ProjectInfo) {
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

        let dbFile = projectURL.appendingPathComponent(".beads/beadster.db")

        guard FileManager.default.fileExists(atPath: dbFile.path) else {
            projectURL.stopAccessingSecurityScopedResource()
            print("No beadster.db found for \(project.name)")
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
                await self?.syncProject(project)
            }
        }

        source.setCancelHandler {
            close(fd)
            projectURL.stopAccessingSecurityScopedResource()
        }

        source.resume()

        watchers[project.id] = source
        print("Started watching: \(dbFile.path)")
    }

    func stopWatching(projectId: String) {
        watchers[projectId]?.cancel()
        watchers.removeValue(forKey: projectId)
    }

    func stopAllWatchers() {
        for (_, watcher) in watchers {
            watcher.cancel()
        }
        watchers.removeAll()
    }

    // MARK: - Sync

    func syncAll() async {
        print("Syncing all projects...")
        // TODO: implement when we have project store reference
    }

    func syncProject(_ project: ProjectInfo) async {
        guard !isSyncing else {
            print("Sync already in progress")
            return
        }

        isSyncing = true
        defer { isSyncing = false }

        print("Syncing project: \(project.name)")

        do {
            // resolve bookmark
            var isStale = false
            guard let projectURL = try? URL(
                resolvingBookmarkData: project.bookmark,
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
            guard let sourceId = project.sourceId else {
                print("No source ID - skipping cloud sync for now")
                lastSyncDate = Date()
                syncError = nil
                return
            }

            // 3. Get remote issues
            let remoteIssues = try await APIClient.shared.getIssues(sourceId: sourceId)
            print("Found \(remoteIssues.count) remote issues")

            // 4. Push to cloud (one-way sync for POC)
            // For now: SQLite is read-only (managed by bd CLI)
            // Cloud changes would be applied by running bd CLI commands
            let response = try await APIClient.shared.syncIssues(sourceId: sourceId, issues: localIssues)
            print("Sync result: created=\(response.created), updated=\(response.updated), skipped=\(response.skipped)")

            lastSyncDate = Date()
            syncError = nil

            print("Sync completed successfully")

        } catch {
            print("Sync failed: \(error)")
            syncError = error.localizedDescription
        }
    }

    func manualSync(project: ProjectInfo) async {
        await syncProject(project)
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
}

// MARK: - Errors

enum SyncError: LocalizedError {
    case bookmarkFailed
    case accessDenied
    case networkError
    case mergeConflict

    var errorDescription: String? {
        switch self {
        case .bookmarkFailed: return "Failed to resolve project bookmark"
        case .accessDenied: return "Access denied to project folder"
        case .networkError: return "Network error during sync"
        case .mergeConflict: return "Merge conflict detected"
        }
    }
}
