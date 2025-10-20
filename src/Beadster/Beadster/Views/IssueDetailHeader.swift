//
//  IssueDetailHeader.swift
//  Beadster
//
//  Created by Anton Podviaznikov on 10/19/25.
//

import SwiftUI

struct IssueDetailHeader: View {
    let issue: Issue
    @ObservedObject var issueStore: IssueStore
    @ObservedObject var projectStore: ProjectStore
    @Binding var contentMode: ContentMode

    var body: some View {
        HStack(spacing: 12) {
            // Back button
            Button(action: {
                contentMode = .issuesList
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11))
                    Text("Back")
                        .font(.system(size: 12))
                }
                .foregroundColor(.blue)
            }
            .buttonStyle(.plain)

            Spacer()

            // Mark as done/open button
            Button(action: {
                print("IssueDetailHeader: Done/Reopen button tapped for issue \(issue.id)")
                if let project = projectStore.selectedProject {
                    let newStatus = issue.status == "closed" ? "open" : "closed"
                    print("IssueDetailHeader: Changing status from '\(issue.status)' to '\(newStatus)'")
                    print("IssueDetailHeader: Project path: \(project.path)")
                    Task {
                        do {
                            // Write to JSONL to persist the change
                            print("IssueDetailHeader: Calling updateIssue...")
                            try await issueStore.updateIssue(
                                projectPath: project.path,
                                issueId: issue.id,
                                title: nil,
                                description: nil,
                                status: newStatus,
                                priority: nil
                            )
                            print("IssueDetailHeader: updateIssue completed, reloading issues...")
                            // Reload issues from the updated JSONL
                            await issueStore.loadIssues(for: project)
                            print("IssueDetailHeader: Issues reloaded")
                            // Update view with the refreshed issue
                            if let updatedIssue = issueStore.issues.first(where: { $0.id == issue.id }) {
                                print("IssueDetailHeader: Updating contentMode with refreshed issue")
                                contentMode = .issueDetail(updatedIssue)
                            }
                        } catch {
                            print("IssueDetailHeader: ERROR - Failed to update issue status: \(error)")
                        }
                    }
                } else {
                    print("IssueDetailHeader: ERROR - No project selected!")
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: issue.status == "closed" ? "circle" : "checkmark.circle.fill")
                        .font(.system(size: 13))
                    Text(issue.status == "closed" ? "Reopen" : "Done")
                        .font(.system(size: 12))
                }
                .foregroundColor(issue.status == "closed" ? .blue : .green)
            }
            .buttonStyle(.plain)

            // Delete button
            Button(action: {
                if let project = projectStore.selectedProject {
                    Task {
                        do {
                            try await issueStore.deleteIssue(projectPath: project.path, issueId: issue.id)
                            await issueStore.loadIssues(for: project)
                            contentMode = .issuesList
                        } catch {
                            print("Failed to delete issue: \(error)")
                        }
                    }
                }
            }) {
                Image(systemName: "trash")
                    .font(.system(size: 13))
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .frame(height: LayoutConstants.contentHeaderHeight)
        .background(AppConfig.showDebugColors ? Color.green.opacity(0.3) : Color.clear)
        .border(AppConfig.showDebugColors ? Color.green : Color.clear, width: 2)
    }
}
