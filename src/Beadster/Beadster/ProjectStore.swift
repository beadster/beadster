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
    @Published var errorMessage: String?
    @Published var isScanning = false

    private let bookmarksKey = "project_bookmarks"

    init() {
        loadProjects()
        print("ProjectStore: Loaded \(projects.count) projects")
    }

    // MARK: - Project Discovery

    func selectFolderToScan() {
        print("ProjectStore: Opening folder selection dialog")

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a folder to scan for projects with .beads directories"
        panel.prompt = "Scan"

        print("ProjectStore: Showing panel...")
        let response = panel.runModal()
        print("ProjectStore: Panel response: \(response.rawValue)")

        if response == .OK, let url = panel.url {
            print("ProjectStore: Selected folder: \(url.path)")
            Task {
                await scanFolder(url)
            }
        } else {
            print("ProjectStore: No folder selected or cancelled")
        }
    }

    func scanFolder(_ rootURL: URL) async {
        print("ProjectStore: Starting scan of \(rootURL.path)")
        isScanning = true
        defer { isScanning = false }

        // create security bookmark
        print("ProjectStore: Creating security bookmark...")
        guard let bookmark = try? rootURL.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else {
            let error = "Failed to create security bookmark for \(rootURL.path)"
            print("ProjectStore: ERROR - \(error)")
            errorMessage = error
            return
        }
        print("ProjectStore: Bookmark created successfully")

        // start accessing
        print("ProjectStore: Starting security scoped access...")
        guard rootURL.startAccessingSecurityScopedResource() else {
            let error = "Failed to access \(rootURL.path) - check sandbox permissions"
            print("ProjectStore: ERROR - \(error)")
            errorMessage = error
            return
        }
        defer {
            print("ProjectStore: Stopping security scoped access")
            rootURL.stopAccessingSecurityScopedResource()
        }

        print("ProjectStore: Scanning for .beads directories...")
        // scan for .beads directories
        let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        var found = 0
        while let url = enumerator?.nextObject() as? URL {
            let beadsDir = url.appendingPathComponent(".beads")
            if FileManager.default.fileExists(atPath: beadsDir.path) {
                print("ProjectStore: Found .beads at \(url.path)")
                await addProject(url)
                found += 1
            }
        }

        print("ProjectStore: Scan complete - found \(found) projects")
        errorMessage = found > 0 ? nil : "No projects with .beads directories found"
    }

    func addProject(_ projectURL: URL) async {
        print("ProjectStore: Adding project \(projectURL.path)")

        // check if already added
        if projects.contains(where: { $0.path == projectURL.path }) {
            print("ProjectStore: Project already exists - skipping")
            return
        }

        // create security bookmark for this project
        print("ProjectStore: Creating project bookmark...")
        guard let bookmark = try? projectURL.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else {
            print("ProjectStore: ERROR - Failed to create project bookmark")
            errorMessage = "Failed to create bookmark for \(projectURL.lastPathComponent)"
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
        print("ProjectStore: Added project, now have \(projects.count) total")
        saveProjects()

        // start watching this project
        print("ProjectStore: Starting file watcher for \(project.name)")
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
