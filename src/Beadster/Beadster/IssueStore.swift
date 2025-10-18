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
    @Published var filter: IssueFilter = .all
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

    // MARK: - Issue Editing (via bd CLI)

    func createIssue(projectPath: String, title: String, description: String?, priority: Int, labels: [String]) async throws {
        var command = "cd \"\(projectPath)\" && bd create \"\(escapeForShell(title))\" --priority=\(priority)"

        if let desc = description, !desc.isEmpty {
            command += " --description=\"\(escapeForShell(desc))\""
        }

        if !labels.isEmpty {
            let labelsStr = labels.map { escapeForShell($0) }.joined(separator: ",")
            command += " --labels=\"\(labelsStr)\""
        }

        try await runBdCommand(command)
    }

    func updateIssue(projectPath: String, issueId: String, title: String?, description: String?, status: String?, priority: Int?) async throws {
        var command = "cd \"\(projectPath)\" && bd update \(issueId)"

        if let title = title {
            command += " --title=\"\(escapeForShell(title))\""
        }

        if let description = description {
            command += " --description=\"\(escapeForShell(description))\""
        }

        if let status = status {
            command += " --status=\(status)"
        }

        if let priority = priority {
            command += " --priority=\(priority)"
        }

        try await runBdCommand(command)
    }

    func deleteIssue(projectPath: String, issueId: String) async throws {
        let command = "cd \"\(projectPath)\" && bd delete \(issueId)"
        try await runBdCommand(command)
    }

    private func runBdCommand(_ command: String) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw IssueEditError.commandFailed(errorOutput)
        }
    }

    private func escapeForShell(_ str: String) -> String {
        return str.replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "`", with: "\\`")
    }
}

enum IssueEditError: LocalizedError {
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let error):
            return "bd command failed: \(error)"
        }
    }
}

enum IssueFilter: String, CaseIterable {
    case all = "All"
    case open = "Open"
    case closed = "Closed"
}
