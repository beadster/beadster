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

        // read from .beads/beadster.db
        let dbPath = projectURL.appendingPathComponent(".beads/beadster.db")
        print("IssueStore: Reading from \(dbPath.path)")

        do {
            let db = BeadsDatabase(beadsDir: projectURL)
            try db.open()
            defer { db.close() }

            let localIssues = try db.getAllIssues()
            print("IssueStore: Loaded \(localIssues.count) issues")
            await MainActor.run {
                self.issues = localIssues
            }
        } catch DatabaseError.cantOpen {
            print("IssueStore: ERROR - No .beads/beadster.db found")
            await MainActor.run {
                self.issues = []
            }
        } catch {
            print("IssueStore: ERROR loading issues: \(error)")
            await MainActor.run {
                self.issues = []
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
                issue.description?.lowercased().contains(search) == true ||
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
                guard let labels = issue.labels else { return false }
                return !selectedLabels.isDisjoint(with: labels)
            }
        }

        return filtered
    }

    func allLabels() -> [String] {
        var labels = Set<String>()
        for issue in issues {
            if let issueLabels = issue.labels {
                labels.formUnion(issueLabels)
            }
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
        guard let index = issues.firstIndex(where: { $0.id == issue.id }) else { return }

        var updated = issue
        updated.status = issue.status == "closed" ? "open" : "closed"
        updated.updatedAt = Date()
        if updated.status == "closed" {
            updated.closedAt = Date()
        } else {
            updated.closedAt = nil
        }

        issues[index] = updated
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
        let now = Date()
        let newIssue = Issue(
            id: newId,
            title: title,
            description: description,
            status: "open",
            priority: priority,
            issueType: "task",
            labels: labels.isEmpty ? nil : labels,
            assignee: nil,
            design: nil,
            acceptanceCriteria: nil,
            notes: nil,
            dueAt: nil,
            createdAt: now,
            updatedAt: now,
            closedAt: nil
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
        let projectURL = URL(fileURLWithPath: projectPath)

        // read existing issues
        var allIssues = try JSONLManager.readIssues(from: projectURL)

        // find and update the issue
        guard let index = allIssues.firstIndex(where: { $0.id == issueId }) else {
            throw IssueEditError.issueNotFound(issueId)
        }

        var updated = allIssues[index]
        if let title = title {
            updated.title = title
        }
        if let description = description {
            updated.description = description
        }
        if let status = status {
            updated.status = status
            if status == "closed" && updated.closedAt == nil {
                updated.closedAt = Date()
            }
        }
        if let priority = priority {
            updated.priority = priority
        }
        updated.updatedAt = Date()

        allIssues[index] = updated

        // write back
        try JSONLManager.writeIssues(allIssues, to: projectURL)

        // update local state
        await MainActor.run {
            if let localIndex = self.issues.firstIndex(where: { $0.id == issueId }) {
                self.issues[localIndex] = updated
            }
        }
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
