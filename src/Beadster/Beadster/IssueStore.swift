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
