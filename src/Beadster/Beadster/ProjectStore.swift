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

        // register any projects without sourceId
        Task {
            await registerUnregisteredProjects()
        }
    }

    private func registerUnregisteredProjects() async {
        var needsSave = false

        for (index, project) in projects.enumerated() where project.sourceId == nil {
            print("ProjectStore: Auto-registering project: \(project.name)")

            // generate source ID
            let sourceId = "src_\(UUID().uuidString.prefix(12))"

            // resolve bookmark
            var isStale = false
            guard let projectURL = try? URL(
                resolvingBookmarkData: project.bookmark,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else {
                print("ProjectStore: Failed to resolve bookmark for \(project.name)")
                continue
            }

            // create updated project with sourceId
            let updatedProject = ProjectInfo(
                id: project.id,
                name: project.name,
                path: project.path,
                bookmark: project.bookmark,
                lastSync: project.lastSync,
                sourceId: sourceId
            )

            // register with cloud
            do {
                _ = try await registerProjectSource(project: updatedProject, projectURL: projectURL)
                print("ProjectStore: Auto-registered source: \(sourceId)")

                // update in array
                await MainActor.run {
                    projects[index] = updatedProject
                }
                needsSave = true
            } catch {
                print("ProjectStore: WARNING - Auto-registration failed for \(project.name): \(error)")
            }
        }

        if needsSave {
            saveProjects()
        }
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

        await MainActor.run {
            isScanning = true
        }

        defer {
            Task { @MainActor in
                isScanning = false
            }
        }

        // create security bookmark
        print("ProjectStore: Creating security bookmark...")
        guard let bookmark = try? rootURL.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else {
            let error = "Failed to create security bookmark for \(rootURL.path)"
            print("ProjectStore: ERROR - \(error)")
            await MainActor.run {
                errorMessage = error
            }
            return
        }
        print("ProjectStore: Bookmark created successfully")

        // start accessing
        print("ProjectStore: Starting security scoped access...")
        guard rootURL.startAccessingSecurityScopedResource() else {
            let error = "Failed to access \(rootURL.path) - check sandbox permissions"
            print("ProjectStore: ERROR - \(error)")
            await MainActor.run {
                errorMessage = error
            }
            return
        }
        defer {
            print("ProjectStore: Stopping security scoped access")
            rootURL.stopAccessingSecurityScopedResource()
        }

        print("ProjectStore: Scanning for .beads directories...")

        var found = 0

        // check root folder itself first
        let rootBeadsDB = rootURL.appendingPathComponent(".beads/beadster.db")
        if FileManager.default.fileExists(atPath: rootBeadsDB.path) {
            print("ProjectStore: Found .beads/beadster.db at root: \(rootURL.path)")
            await addProject(rootURL)
            found += 1
        }

        // then scan subdirectories
        let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [] // don't skip hidden files since .beads is hidden
        )

        while let url = enumerator?.nextObject() as? URL {
            // skip the .beads directory itself and other dot directories
            if url.lastPathComponent.hasPrefix(".") {
                continue
            }

            let beadsDB = url.appendingPathComponent(".beads/beadster.db")
            if FileManager.default.fileExists(atPath: beadsDB.path) {
                print("ProjectStore: Found .beads/beadster.db at \(url.path)")
                await addProject(url)
                found += 1
            }
        }

        print("ProjectStore: Scan complete - found \(found) projects")

        await MainActor.run {
            errorMessage = found > 0 ? nil : "No projects with .beads/beadster.db found"
        }
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
            await MainActor.run {
                errorMessage = "Failed to create bookmark for \(projectURL.lastPathComponent)"
            }
            return
        }

        // generate source ID
        let sourceId = "src_\(UUID().uuidString.prefix(12))"

        var project = ProjectInfo(
            id: UUID().uuidString,
            name: projectURL.lastPathComponent,
            path: projectURL.path,
            bookmark: bookmark,
            lastSync: nil,
            sourceId: sourceId
        )

        // register source with cloud
        print("ProjectStore: Registering source with cloud...")
        do {
            _ = try await registerProjectSource(project: project, projectURL: projectURL)
            print("ProjectStore: Source registered successfully: \(sourceId)")
        } catch {
            print("ProjectStore: WARNING - Source registration failed: \(error)")
            // Continue anyway - will try to register on first sync
        }

        await MainActor.run {
            projects.append(project)
        }
        print("ProjectStore: Added project, now have \(projects.count) total")
        saveProjects()

        // start watching this project
        print("ProjectStore: Starting file watcher for \(project.name)")
        SyncDaemon.shared.startWatching(project: project)
    }

    private func registerProjectSource(project: ProjectInfo, projectURL: URL) async throws -> String {
        guard let sourceId = project.sourceId else {
            throw NSError(domain: "ProjectStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "No source ID"])
        }

        // access security scoped resource
        guard projectURL.startAccessingSecurityScopedResource() else {
            throw NSError(domain: "ProjectStore", code: 2, userInfo: [NSLocalizedDescriptionKey: "Access denied"])
        }
        defer { projectURL.stopAccessingSecurityScopedResource() }

        // read issues from database
        let db = BeadsDatabase(beadsDir: projectURL)
        try db.open()
        defer { db.close() }

        let issues = try db.getAllIssues()

        // register with API
        let sourcePayload = SourcePayload(
            id: sourceId,
            name: project.name,
            type: "local",
            path: project.path
        )

        return try await APIClient.shared.registerSource(source: sourcePayload, issues: issues)
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

        let loadedProjects = projectData.compactMap { dict -> ProjectInfo? in
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

            let project = ProjectInfo(
                id: id,
                name: name,
                path: path,
                bookmark: bookmark,
                lastSync: nil,
                sourceId: dict["sourceId"] as? String
            )

            // start watching loaded projects
            Task { @MainActor in
                SyncDaemon.shared.startWatching(project: project)
            }

            return project
        }

        projects = loadedProjects
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
