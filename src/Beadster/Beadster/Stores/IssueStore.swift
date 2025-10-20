//
//  IssueStore.swift
//  Beadster
//
//  Created by Anton Podviaznikov on 10/18/25.
//

import Foundation


@MainActor
class IssueStore: ObservableObject {
    @Published var issues: [Issue] = []
    @Published var dependencies: [IssueDependency] = []
    @Published var isLoading = false
    @Published var filter: IssueFilter = .open
    @Published var searchText: String = ""
    @Published var selectedPriority: Int? = nil
    @Published var selectedLabels: Set<String> = []
    @Published var selectedProjectId: String? = nil  // nil means "All"

    func loadIssues(for project: ProjectInfo) async {
        print("IssueStore: Loading issues for \(project.name)")

        await MainActor.run {
            isLoading = true
        }

        defer {
            Task { @MainActor in
                isLoading = false
            }
        }

        // resolve bookmark
        var isStale = false
        guard let projectURL = try? URL(
            resolvingBookmarkData: project.bookmark,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            print("IssueStore: ERROR - Failed to resolve bookmark for \(project.name)")
            await MainActor.run {
                self.issues = []
            }
            return
        }

        print("IssueStore: Resolved URL: \(projectURL.path)")

        // access security scoped resource
        guard projectURL.startAccessingSecurityScopedResource() else {
            print("IssueStore: ERROR - Failed to access \(projectURL)")
            await MainActor.run {
                self.issues = []
            }
            return
        }
        defer {
            print("IssueStore: Stopping security scoped access")
            projectURL.stopAccessingSecurityScopedResource()
        }

        // HYBRID READ: SQLite baseline + JSONL delta
        // This ensures we see latest changes even if bd database is stale
        print("IssueStore: Reading from beads database (baseline)")

        do {
            // Read ALL issues from JSONL (source of truth)
            let jsonlIssues = try JSONLManager.readIssues(from: projectURL)
            print("IssueStore: JSONL is source of truth - loaded \(jsonlIssues.count) issues")

            // Try to load dependencies from database if it exists
            var localDependencies: [IssueDependency] = []
            if let dbURL = BeadsHelper.findDatabaseFile(in: projectURL) {
                do {
                    let db = BeadsDatabase(beadsDir: projectURL)
                    try db.open()
                    defer { db.close() }
                    localDependencies = try db.getAllDependencies()
                    print("IssueStore: Loaded \(localDependencies.count) dependencies from database")
                } catch {
                    print("IssueStore: Could not load dependencies from database: \(error)")
                }
            } else {
                print("IssueStore: No database found, skipping dependencies")
            }

            await MainActor.run {
                self.issues = jsonlIssues
                self.dependencies = localDependencies
            }
        } catch {
            print("IssueStore: ERROR loading issues from JSONL: \(error)")
            await MainActor.run {
                self.issues = []
                self.dependencies = []
            }
        }
    }

    func loadIssuesFromAllProjects(projects: [ProjectInfo]) async {
        print("IssueStore: Loading issues from ALL \(projects.count) projects")

        await MainActor.run {
            isLoading = true
        }

        defer {
            Task { @MainActor in
                isLoading = false
            }
        }

        var allIssues: [Issue] = []
        var allDependencies: [IssueDependency] = []

        for project in projects {
            print("IssueStore: Loading from project: \(project.name)")

            // resolve bookmark
            var isStale = false
            guard let projectURL = try? URL(
                resolvingBookmarkData: project.bookmark,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else {
                print("IssueStore: ERROR - Failed to resolve bookmark for \(project.name)")
                continue
            }

            // access security scoped resource
            guard projectURL.startAccessingSecurityScopedResource() else {
                print("IssueStore: ERROR - Failed to access \(projectURL)")
                continue
            }
            defer { projectURL.stopAccessingSecurityScopedResource() }

            // Read issues from JSONL (source of truth)
            do {
                // Read ALL issues from JSONL (source of truth)
                let jsonlIssues = try JSONLManager.readIssues(from: projectURL)

                // Set projectName on all JSONL issues
                let issuesWithProject = jsonlIssues.map { issue in
                    var updated = issue
                    updated.projectName = project.name
                    return updated
                }

                // Try to load dependencies from database if it exists
                var projectDependencies: [IssueDependency] = []
                if let dbURL = BeadsHelper.findDatabaseFile(in: projectURL) {
                    do {
                        let db = BeadsDatabase(beadsDir: projectURL)
                        try db.open()
                        defer { db.close() }
                        projectDependencies = try db.getAllDependencies()
                        print("IssueStore: Loaded \(projectDependencies.count) dependencies from \(project.name)")
                    } catch {
                        print("IssueStore: Could not load dependencies from \(project.name): \(error)")
                    }
                } else {
                    print("IssueStore: No database found for \(project.name), skipping dependencies")
                }

                print("IssueStore: Loaded \(issuesWithProject.count) issues from \(project.name)")
                allIssues.append(contentsOf: issuesWithProject)
                allDependencies.append(contentsOf: projectDependencies)
            } catch {
                print("IssueStore: ERROR loading issues from \(project.name): \(error)")
            }
        }

        print("IssueStore: Total loaded: \(allIssues.count) issues from all projects")
        await MainActor.run {
            self.issues = allIssues
            self.dependencies = allDependencies
        }
    }

    func filteredIssues() -> [Issue] {
        var filtered = issues

        // filter by project
        if let projectId = selectedProjectId {
            filtered = filtered.filter { $0.projectName == projectId }
        }

        // filter by status
        switch filter {
        case .all:
            break
        case .open:
            filtered = filtered.filter { $0.status == "open" || $0.status == "in_progress" }
        case .closed:
            filtered = filtered.filter { $0.status == "closed" }
        }

        // filter by search text
        if !searchText.isEmpty {
            let search = searchText.lowercased()
            filtered = filtered.filter { issue in
                issue.title.lowercased().contains(search) ||
                issue.body?.lowercased().contains(search) == true ||
                issue.id.lowercased().contains(search)
            }
        }

        // filter by priority
        if let priority = selectedPriority {
            filtered = filtered.filter { $0.priority == priority }
        }

        // filter by labels
        if !selectedLabels.isEmpty {
            filtered = filtered.filter { issue in
                !selectedLabels.isDisjoint(with: issue.labels)
            }
        }

        return filtered
    }

    func allLabels() -> [String] {
        var labels = Set<String>()
        for issue in issues {
            labels.formUnion(issue.labels)
        }
        return labels.sorted()
    }

    func clearFilters() {
        searchText = ""
        selectedPriority = nil
        selectedLabels.removeAll()
        filter = .all
    }

    func toggleIssueStatus(_ issue: Issue) {
        // This is a local-only preview update for immediate UI feedback
        // The real update happens through updateIssue() which writes to JSONL
        guard let index = issues.firstIndex(where: { $0.id == issue.id }) else { return }

        var updated = issue
        updated.status = issue.status == "closed" ? "open" : "closed"
        updated.updatedAt = Int(Date().timeIntervalSince1970)
        if updated.status == "closed" {
            updated.closedAt = Int(Date().timeIntervalSince1970)
        } else {
            updated.closedAt = nil
        }

        issues[index] = updated

        // NOTE: This only updates local state for immediate UI feedback
        // To persist changes, caller should use updateIssue() to write to JSONL
    }

    // MARK: - Issue Editing (direct JSONL write)

    func createIssue(projectPath: String, title: String, description: String?, priority: Int, status: String = "open", issueType: String = "task", labels: [String]) async throws {
        let projectURL = URL(fileURLWithPath: projectPath)

        // read existing issues
        let existingIssues = try JSONLManager.readIssues(from: projectURL)

        // generate next issue ID
        let projectName = projectURL.lastPathComponent
        let nextNumber = getNextIssueNumber(existingIssues: existingIssues, projectName: projectName)
        let newId = "\(projectName)-\(nextNumber)"

        // create new issue
        let now = Int(Date().timeIntervalSince1970)
        let newIssue = Issue(
            id: newId,
            title: title,
            body: description,
            status: status,
            priority: priority,
            issueType: issueType,
            labels: labels,
            assignee: nil,
            design: nil,
            acceptanceCriteria: nil,
            notes: nil,
            createdAt: now,
            updatedAt: now,
            closedAt: nil,
            sessionId: nil,
            client: nil,
            projectName: nil
        )

        // append to issues and write
        var allIssues = existingIssues
        allIssues.append(newIssue)
        try JSONLManager.writeIssues(allIssues, to: projectURL)

        // update local state
        await MainActor.run {
            self.issues.append(newIssue)
        }
    }

    func updateIssue(projectPath: String, issueId: String, title: String?, description: String?, status: String?, priority: Int?) async throws {
        print("IssueStore: updateIssue called for \(issueId)")
        print("IssueStore: projectPath=\(projectPath)")
        print("IssueStore: status=\(status ?? "nil")")

        let projectURL = URL(fileURLWithPath: projectPath)

        // read existing issues
        print("IssueStore: Reading issues from JSONL at \(projectURL.path)")
        var allIssues = try JSONLManager.readIssues(from: projectURL)
        print("IssueStore: Read \(allIssues.count) issues from JSONL")

        // find the issue - if not found, try to pull from cloud first
        var index = allIssues.firstIndex(where: { $0.id == issueId })

        if index == nil {
            print("IssueStore: Issue \(issueId) not found in JSONL - attempting to pull from cloud")

            // try to fetch from cloud and add to local JSONL
            if let cloudIssue = try await fetchIssueFromCloud(issueId: issueId) {
                print("IssueStore: Found issue in cloud, adding to local JSONL")
                allIssues.append(cloudIssue)
                index = allIssues.count - 1

                // write to JSONL to persist the cloud issue locally
                try JSONLManager.writeIssues(allIssues, to: projectURL)
                print("IssueStore: Added cloud issue to JSONL")
            } else {
                print("IssueStore: ERROR - Issue \(issueId) not found in JSONL or cloud")
                throw IssueEditError.issueNotFound(issueId)
            }
        }

        guard let issueIndex = index else {
            print("IssueStore: ERROR - Issue \(issueId) not found")
            throw IssueEditError.issueNotFound(issueId)
        }

        print("IssueStore: Found issue at index \(issueIndex)")

        var updated = allIssues[issueIndex]
        let oldStatus = updated.status

        if let title = title {
            updated.title = title
        }
        if let description = description {
            updated.body = description
        }
        if let status = status {
            updated.status = status
            if status == "closed" && updated.closedAt == nil {
                updated.closedAt = Int(Date().timeIntervalSince1970)
            }
        }
        if let priority = priority {
            updated.priority = priority
        }
        updated.updatedAt = Int(Date().timeIntervalSince1970)

        allIssues[issueIndex] = updated

        print("IssueStore: Updated issue status from '\(oldStatus)' to '\(updated.status)'")

        // write back to JSONL (source of truth)
        print("IssueStore: Writing \(allIssues.count) issues back to JSONL")
        try JSONLManager.writeIssues(allIssues, to: projectURL)
        print("IssueStore: Successfully wrote to JSONL")

        // NOTE: We do NOT update bd's SQLite database here because:
        // - macOS app is sandboxed (cannot execute bd CLI)
        // - bd CLI will auto-import JSONL on next `bd list` run
        // - Our hybrid read (loadIssues) merges SQLite + JSONL on next load

        // update in-memory state for immediate UI feedback
        await MainActor.run {
            if let localIndex = self.issues.firstIndex(where: { $0.id == issueId }) {
                self.issues[localIndex] = updated
                print("IssueStore: Updated in-memory state at index \(localIndex)")
            }
        }

        print("IssueStore: updateIssue completed for \(issueId)")
    }

    func deleteIssue(projectPath: String, issueId: String) async throws {
        let projectURL = URL(fileURLWithPath: projectPath)

        // read existing issues
        var allIssues = try JSONLManager.readIssues(from: projectURL)

        // remove the issue
        guard let index = allIssues.firstIndex(where: { $0.id == issueId }) else {
            throw IssueEditError.issueNotFound(issueId)
        }

        allIssues.remove(at: index)

        // write back
        try JSONLManager.writeIssues(allIssues, to: projectURL)

        // update local state
        await MainActor.run {
            self.issues.removeAll(where: { $0.id == issueId })
        }
    }

    private func fetchIssueFromCloud(issueId: String) async throws -> Issue? {
        // Get API token from AuthManager
        guard let apiToken = AuthManager.shared.getAPIKey() else {
            print("IssueStore: No API token - cannot fetch from cloud")
            return nil
        }

        // Call API to get issue by beads_id
        let urlString = "https://api.beadster.ai/v1/issues?beads_id=\(issueId)"
        guard let url = URL(string: urlString) else {
            print("IssueStore: Invalid URL")
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                print("IssueStore: Failed to fetch issue from cloud - invalid response")
                return nil
            }

            let decoder = JSONDecoder()

            // API returns {"issues": [...]} with database id, not beads_id
            // We need to decode manually and fix the id field
            struct APIIssue: Codable {
                let id: String  // database composite id
                let beads_id: String  // the actual beadster id we want
                let title: String
                let body: String?
                let status: String
                let priority: String
                let labels: [String]  // Already parsed array
                let created_at: Int
                let updated_at: Int
                let closed_at: Int?
                let git_repo_url: String?
                let git_branch: String?
                let git_commit_hash: String?
                let git_is_dirty: Int?
            }

            struct IssuesResponse: Codable {
                let issues: [APIIssue]
            }

            let apiResponse = try decoder.decode(IssuesResponse.self, from: data)

            // Find the issue and convert to Issue model with beads_id as id
            guard let apiIssue = apiResponse.issues.first(where: { $0.beads_id == issueId }) else {
                return nil
            }

            // Convert priority string to int (handling "1.0" -> 1)
            let priority: Int
            if let priorityDouble = Double(apiIssue.priority) {
                priority = Int(priorityDouble)
            } else {
                priority = 2  // default
            }

            // Convert git_is_dirty from Int to Bool
            let gitIsDirty: Bool?
            if let isDirtyInt = apiIssue.git_is_dirty {
                gitIsDirty = isDirtyInt != 0
            } else {
                gitIsDirty = nil
            }

            // Create Issue with beads_id as id
            let issue = Issue(
                id: apiIssue.beads_id,  // Use beads_id, not database id!
                title: apiIssue.title,
                body: apiIssue.body,
                status: apiIssue.status,
                priority: priority,
                issueType: nil,
                labels: apiIssue.labels,
                assignee: nil,
                design: nil,
                acceptanceCriteria: nil,
                notes: nil,
                createdAt: apiIssue.created_at,
                updatedAt: apiIssue.updated_at,
                closedAt: apiIssue.closed_at,
                sessionId: nil,
                client: nil,
                projectName: nil,
                gitRepoUrl: apiIssue.git_repo_url,
                gitBranch: apiIssue.git_branch,
                gitCommitHash: apiIssue.git_commit_hash,
                gitIsDirty: gitIsDirty
            )

            return issue

        } catch {
            print("IssueStore: Error fetching from cloud: \(error)")
            return nil
        }
    }

    private func getNextIssueNumber(existingIssues: [Issue], projectName: String) -> Int {
        let prefix = "\(projectName)-"
        let numbers = existingIssues
            .map { $0.id }
            .filter { $0.hasPrefix(prefix) }
            .compactMap { id -> Int? in
                let numberPart = id.dropFirst(prefix.count)
                return Int(numberPart)
            }

        return (numbers.max() ?? 0) + 1
    }
}

enum IssueEditError: LocalizedError {
    case issueNotFound(String)
    case fileWriteError(Error)

    var errorDescription: String? {
        switch self {
        case .issueNotFound(let id):
            return "Issue not found: \(id)"
        case .fileWriteError(let error):
            return "Failed to write issues: \(error.localizedDescription)"
        }
    }
}

enum IssueFilter: String, CaseIterable {
    case open = "Open"
    case all = "All"
    case closed = "Closed"
}
