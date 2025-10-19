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

        // read from .beads database
        print("IssueStore: Reading from beads database")

        do {
            let db = BeadsDatabase(beadsDir: projectURL)
            try db.open()
            defer { db.close() }

            let localIssues = try db.getAllIssues()
            let localDependencies = try db.getAllDependencies()
            print("IssueStore: Loaded \(localIssues.count) issues and \(localDependencies.count) dependencies")
            await MainActor.run {
                self.issues = localIssues
                self.dependencies = localDependencies
            }
        } catch DatabaseError.cantOpen {
            print("IssueStore: ERROR - No beads database found")
            await MainActor.run {
                self.issues = []
                self.dependencies = []
            }
        } catch {
            print("IssueStore: ERROR loading issues: \(error)")
            await MainActor.run {
                self.issues = []
                self.dependencies = []
            }
        }
    }

    func filteredIssues() -> [Issue] {
        var filtered = issues

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

    func createIssue(projectPath: String, title: String, description: String?, priority: Int, labels: [String]) async throws {
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
            status: "open",
            priority: priority,
            issueType: "task",
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

        // find and update the issue
        guard let index = allIssues.firstIndex(where: { $0.id == issueId }) else {
            print("IssueStore: ERROR - Issue \(issueId) not found in JSONL")
            throw IssueEditError.issueNotFound(issueId)
        }

        print("IssueStore: Found issue at index \(index)")

        var updated = allIssues[index]
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

        allIssues[index] = updated

        print("IssueStore: Updated issue status from '\(oldStatus)' to '\(updated.status)'")

        // write back
        print("IssueStore: Writing \(allIssues.count) issues back to JSONL")
        try JSONLManager.writeIssues(allIssues, to: projectURL)
        print("IssueStore: Successfully wrote to JSONL")

        // update local state
        await MainActor.run {
            if let localIndex = self.issues.firstIndex(where: { $0.id == issueId }) {
                self.issues[localIndex] = updated
                print("IssueStore: Updated local state at index \(localIndex)")
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
