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

    func loadIssues(for project: ProjectInfo) async {
        isLoading = true
        defer { isLoading = false }

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
        defer { projectURL.stopAccessingSecurityScopedResource() }

        // read from .beads/issues.jsonl
        do {
            let localIssues = try JSONLManager.readIssues(from: projectURL)
            self.issues = localIssues
        } catch {
            print("Error loading issues: \(error)")
            self.issues = []
        }
    }

    func filteredIssues() -> [Issue] {
        switch filter {
        case .all:
            return issues
        case .open:
            return issues.filter { $0.status == "open" || $0.status == "in_progress" }
        case .closed:
            return issues.filter { $0.status == "closed" }
        }
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
}

enum IssueFilter: String, CaseIterable {
    case all = "All"
    case open = "Open"
    case closed = "Closed"
}
