//
//  ProjectFileWatcher.swift
//  Beadster
//
//  Watches .beads issue files for changes using FSEvents
//

import Foundation

@MainActor
class ProjectFileWatcher: ObservableObject {
    @Published var watchedProjectsCount: Int = 0
    @Published var lastLocalChangeDate: Date?

    private struct ProjectWatch {
        let watcher: FileWatcher
        let scopedURL: URL
    }

    private var watchers: [String: ProjectWatch] = [:]
    private var pendingReloadTasks: [String: Task<Void, Never>] = [:]
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

        let beadsURL = projectURL.appendingPathComponent(".beads", isDirectory: true)
        let watchedURL = FileManager.default.fileExists(atPath: beadsURL.path) ? beadsURL : projectURL

        let watcher = FileWatcher(path: watchedURL.path) { [weak self] in
            Task { @MainActor in
                self?.scheduleReload(for: project)
            }
        }

        watcher.start()

        Task { @MainActor [weak self] in
            self?.pendingReloadTasks[project.id]?.cancel()
            self?.pendingReloadTasks.removeValue(forKey: project.id)
            self?.watchers[project.id]?.watcher.stop()
            self?.watchers[project.id]?.scopedURL.stopAccessingSecurityScopedResource()
            self?.watchers[project.id] = ProjectWatch(
                watcher: watcher,
                scopedURL: projectURL
            )
            self?.watchedProjectsCount = self?.watchers.count ?? 0
            print("Started watching: \(watchedURL.path)")
            print("📊 Watched projects count: \(self?.watchedProjectsCount ?? 0)")
        }
    }

    func stopWatching(projectId: String) {
        pendingReloadTasks[projectId]?.cancel()
        pendingReloadTasks.removeValue(forKey: projectId)
        watchers[projectId]?.watcher.stop()
        watchers[projectId]?.scopedURL.stopAccessingSecurityScopedResource()
        watchers.removeValue(forKey: projectId)
        watchedProjectsCount = watchers.count
    }

    func stopAllWatchers() {
        for (_, task) in pendingReloadTasks {
            task.cancel()
        }
        pendingReloadTasks.removeAll()

        for (_, watch) in watchers {
            watch.watcher.stop()
            watch.scopedURL.stopAccessingSecurityScopedResource()
        }
        watchers.removeAll()
        watchedProjectsCount = 0
    }

    private func scheduleReload(for project: ProjectInfo) {
        pendingReloadTasks[project.id]?.cancel()
        pendingReloadTasks[project.id] = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 250_000_000)
            } catch {
                return
            }

            guard let self else { return }
            self.pendingReloadTasks.removeValue(forKey: project.id)
            self.lastLocalChangeDate = Date()
            print("🔔 .beads changed for \(project.name) - reloading issues")
            await self.syncDelegate?.onFileChanged(project: project)
        }
    }
}

// Delegate protocol for file change notifications
protocol FileSyncDelegate: AnyObject {
    func onFileChanged(project: ProjectInfo) async
}
