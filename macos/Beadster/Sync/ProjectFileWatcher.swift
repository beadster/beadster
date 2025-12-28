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

    private var watchers: [String: [DispatchSourceFileSystemObject]] = [:]
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

        var sources: [DispatchSourceFileSystemObject] = []

        // watch multiple files:
        // - issues.jsonl: source of truth, manual edits
        // - .db: SQLite database for daemon writes (non-WAL mode)
        // - .db-wal: SQLite WAL file (daemon writes in WAL mode)
        let filesToWatch = [
            ".beads/issues.jsonl",
            ".beads/\(project.name).db",
            ".beads/\(project.name).db-wal"
        ]

        for relativePath in filesToWatch {
            let fileURL = projectURL.appendingPathComponent(relativePath)

            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                print("\(relativePath) not accessible for \(project.name)")
                continue
            }

            // open file descriptor
            let fd = open(fileURL.path, O_EVTONLY)
            guard fd >= 0 else {
                print("Failed to open \(fileURL.path), errno: \(errno)")
                continue
            }
            print("✅ Opened fd \(fd) for \(fileURL.path)")

            // create dispatch source
            // Watch for all file system events (write, delete, rename, extend, attrib)
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .delete, .rename, .extend, .attrib],
                queue: DispatchQueue.global()
            )
            print("✅ Created dispatch source for fd \(fd)")

            source.setEventHandler { [weak self] in
                let eventMask = source.data
                print("🔔 File changed: \(fileURL.path) (events: \(eventMask.rawValue))")
                Task { @MainActor in
                    self?.lastLocalChangeDate = Date()
                    await self?.syncDelegate?.onFileChanged(project: project)
                }
            }

            // close fd when cancelled, stop security scoped access on last source
            let isLastFile = (relativePath == filesToWatch.last)
            source.setCancelHandler {
                close(fd)
                if isLastFile {
                    projectURL.stopAccessingSecurityScopedResource()
                }
            }

            source.resume()
            sources.append(source)
            print("Started watching: \(fileURL.path)")
        }

        // store all sources and update count
        if !sources.isEmpty {
            Task { @MainActor [weak self] in
                self?.watchers[project.id] = sources
                self?.watchedProjectsCount = (self?.watchers.count ?? 0)
                print("📊 Watched projects count: \(self?.watchedProjectsCount ?? 0)")
            }
        } else {
            projectURL.stopAccessingSecurityScopedResource()
        }
    }

    func stopWatching(projectId: String) {
        watchers[projectId]?.forEach { $0.cancel() }
        watchers.removeValue(forKey: projectId)
        watchedProjectsCount = watchers.count
    }

    func stopAllWatchers() {
        for (_, sources) in watchers {
            sources.forEach { $0.cancel() }
        }
        watchers.removeAll()
        watchedProjectsCount = 0
    }
}

// Delegate protocol for file change notifications
protocol FileSyncDelegate: AnyObject {
    func onFileChanged(project: ProjectInfo) async
}
