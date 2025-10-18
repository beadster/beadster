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

        let issuesFile = projectURL.appendingPathComponent(".beads/issues.jsonl")

        guard FileManager.default.fileExists(atPath: issuesFile.path) else {
            projectURL.stopAccessingSecurityScopedResource()
            print("No issues.jsonl found for \(project.name)")
            return
        }

        // open file descriptor
        let fd = open(issuesFile.path, O_EVTONLY)
        guard fd >= 0 else {
            projectURL.stopAccessingSecurityScopedResource()
            print("Failed to open \(issuesFile.path)")
            return
        }

        // create dispatch source
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: DispatchQueue.global()
        )

        source.setEventHandler { [weak self] in
            print("File changed: \(issuesFile.path)")
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
        print("Started watching: \(issuesFile.path)")
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

            // 1. Read local issues
            let localIssues = try JSONLManager.readIssues(from: projectURL)
            print("Found \(localIssues.count) local issues")

            // 2. Get remote issues (TODO: need source ID from project)
            // let remoteIssues = try await APIClient.shared.getIssues(sourceId: project.sourceId)

            // 3. Merge (for POC: just push local to remote)
            // let merged = mergeIssues(local: localIssues, remote: remoteIssues)

            // 4. Push to cloud (TODO: implement)
            // let response = try await APIClient.shared.syncIssues(sourceId: project.sourceId, issues: localIssues)

            // 5. Write back to local (TODO: implement)
            // try JSONLManager.writeIssues(merged, to: projectURL)

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
