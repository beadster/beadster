//
//  ProjectStore.swift
//  Beadster
//
//  Created by Anton Podviaznikov on 10/18/25.
//

import Foundation
import AppKit

@MainActor
class ProjectStore: ObservableObject {
    @Published var projects: [ProjectInfo] = []
    @Published var selectedProject: ProjectInfo?

    private let bookmarksKey = "project_bookmarks"

    init() {
        loadProjects()
    }

    // MARK: - Project Discovery

    func selectFolderToScan() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a folder to scan for projects with .beads directories"

        if panel.runModal() == .OK, let url = panel.url {
            Task {
                await scanFolder(url)
            }
        }
    }

    func scanFolder(_ rootURL: URL) async {
        // create security bookmark
        guard let bookmark = try? rootURL.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else {
            print("Failed to create bookmark for \(rootURL)")
            return
        }

        // start accessing
        guard rootURL.startAccessingSecurityScopedResource() else {
            print("Failed to access \(rootURL)")
            return
        }
        defer { rootURL.stopAccessingSecurityScopedResource() }

        // scan for .beads directories
        let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        while let url = enumerator?.nextObject() as? URL {
            let beadsDir = url.appendingPathComponent(".beads")
            if FileManager.default.fileExists(atPath: beadsDir.path) {
                await addProject(url)
            }
        }
    }

    func addProject(_ projectURL: URL) async {
        // create security bookmark for this project
        guard let bookmark = try? projectURL.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else {
            print("Failed to create project bookmark")
            return
        }

        let project = ProjectInfo(
            id: UUID().uuidString,
            name: projectURL.lastPathComponent,
            path: projectURL.path,
            bookmark: bookmark,
            lastSync: nil,
            sourceId: nil
        )

        projects.append(project)
        saveProjects()

        // start watching this project
        SyncDaemon.shared.startWatching(project: project)
    }

    // MARK: - Persistence

    func saveProjects() {
        let projectData = projects.map { project -> [String: Any] in
            var dict: [String: Any] = [
                "id": project.id,
                "name": project.name,
                "path": project.path,
                "bookmark": project.bookmark
            ]
            if let sourceId = project.sourceId {
                dict["sourceId"] = sourceId
            }
            return dict
        }

        UserDefaults.standard.set(projectData, forKey: bookmarksKey)
    }

    func loadProjects() {
        guard let projectData = UserDefaults.standard.array(forKey: bookmarksKey) as? [[String: Any]] else {
            return
        }

        projects = projectData.compactMap { dict in
            guard let id = dict["id"] as? String,
                  let name = dict["name"] as? String,
                  let path = dict["path"] as? String,
                  let bookmark = dict["bookmark"] as? Data else {
                return nil
            }

            // verify bookmark is still valid
            var isStale = false
            guard let _ = try? URL(
                resolvingBookmarkData: bookmark,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else {
                print("Bookmark for \(name) is invalid")
                return nil
            }

            return ProjectInfo(
                id: id,
                name: name,
                path: path,
                bookmark: bookmark,
                lastSync: nil,
                sourceId: dict["sourceId"] as? String
            )
        }
    }

    func removeProject(_ project: ProjectInfo) {
        projects.removeAll { $0.id == project.id }
        saveProjects()

        // stop watching this project
        SyncDaemon.shared.stopWatching(projectId: project.id)
    }
}

// MARK: - ProjectInfo

struct ProjectInfo: Identifiable, Hashable {
    let id: String
    let name: String
    let path: String
    let bookmark: Data
    var lastSync: Date?
    var sourceId: String? // beadster cloud source ID
}
