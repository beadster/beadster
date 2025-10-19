//
//  ProjectFileWatcher.swift
//  Beadster
//
//  Watches .beads database files for changes using DispatchSource
//

import Foundation
import Dispatch

@MainActor
class ProjectFileWatcher: ObservableObject {
    @Published var watchedProjectsCount: Int = 0
    @Published var lastLocalChangeDate: Date?

    private var watchers: [String: DispatchSourceFileSystemObject] = [:]
    private weak var syncDelegate: FileSyncDelegate?

    init(syncDelegate: FileSyncDelegate?) {
        self.syncDelegate = syncDelegate
    }

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
                await self?.syncDelegate?.onFileChanged(project: project)
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
}

// Delegate protocol for file change notifications
protocol FileSyncDelegate: AnyObject {
    func onFileChanged(project: ProjectInfo) async
}
