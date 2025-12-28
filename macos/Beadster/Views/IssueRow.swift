//
//  IssueRow.swift
//  Beadster
//
//  Created by Anton Podviaznikov on 10/19/25.
//

import SwiftUI

// MARK: - Compact Issue Row

struct IssueRowCompact: View {
    let issue: Issue
    @ObservedObject var issueStore: IssueStore
    let viewMode: ViewMode
    let depth: Int
    @EnvironmentObject var projectStore: ProjectStore

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Indentation for tree view
            if depth > 0 {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: CGFloat(depth) * 12)
            }

            // Checkbox
            Button(action: {
                print("IssueRow: Checkbox clicked for issue \(issue.id)")

                // Find project by issue's projectName
                guard let projectName = issue.projectName else {
                    print("IssueRow: ERROR - Issue has no projectName")
                    return
                }

                guard let project = projectStore.projects.first(where: { $0.name == projectName }) else {
                    print("IssueRow: ERROR - Project not found: \(projectName)")
                    return
                }

                let newStatus = issue.status == "closed" ? "open" : "closed"
                print("IssueRow: Changing status from '\(issue.status)' to '\(newStatus)'")

                Task {
                    do {
                        try await issueStore.updateIssue(
                            projectPath: project.path,
                            issueId: issue.id,
                            title: nil,
                            description: nil,
                            status: newStatus,
                            priority: nil
                        )
                        print("IssueRow: Successfully updated issue status")
                    } catch {
                        print("IssueRow: ERROR - Failed to update issue: \(error)")
                    }
                }
            }) {
                Image(systemName: issue.status == "closed" ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundColor(issue.status == "closed" ? .green : .gray)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
            .border(AppConfig.showDebugColors ? Color.cyan : Color.clear, width: 1)

            // Content based on view mode
            switch viewMode {
            case .simple:
                simpleView
            case .extended:
                extendedView
            case .tree:
                // Tree mode will be handled at the list level, for now show simple
                simpleView
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, viewMode == .extended ? 8 : 6)
        .border(AppConfig.showDebugColors ? Color.yellow : Color.clear, width: 2)
    }

    var simpleView: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Row 1: Title and Priority
            HStack(spacing: 8) {
                Text(issue.title)
                    .font(.system(size: 13))
                    .strikethrough(issue.status == "closed")
                    .lineLimit(1)
                    .border(AppConfig.showDebugColors ? Color.red : Color.clear, width: 1)

                Spacer()
                    .border(AppConfig.showDebugColors ? Color.blue : Color.clear, width: 1)

                PriorityBadge(priority: issue.priority)
                    .border(AppConfig.showDebugColors ? Color.green : Color.clear, width: 1)
            }
            .border(AppConfig.showDebugColors ? Color.purple : Color.clear, width: 1)

            // Row 2: Description (optional)
            if let description = issue.body, !description.isEmpty {
                Text(description)
                    .font(.system(size: 11))
                    .foregroundColor(.bdSecondary)
                    .lineLimit(1)
            }

            // Row 3: Project name + Labels
            HStack(spacing: 4) {
                // Project name (first badge)
                if let projectName = issue.projectName {
                    ProjectNameBadge(projectName: projectName)
                }

                // Labels
                if !issue.labels.isEmpty {
                    ForEach(issue.labels.prefix(3), id: \.self) { label in
                        LabelBadge(label: label)
                    }

                    if issue.labels.count > 3 {
                        Text("+\(issue.labels.count - 3)")
                            .font(.system(size: 9))
                            .foregroundColor(.bdSecondary)
                    }
                }
            }
        }
    }

    var extendedView: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Row 1: Title and Priority
            HStack(spacing: 8) {
                Text(issue.title)
                    .font(.system(size: 13))
                    .strikethrough(issue.status == "closed")
                    .lineLimit(1)
                    .border(AppConfig.showDebugColors ? Color.red : Color.clear, width: 1)

                Spacer()
                    .border(AppConfig.showDebugColors ? Color.blue : Color.clear, width: 1)

                PriorityBadge(priority: issue.priority)
                    .border(AppConfig.showDebugColors ? Color.green : Color.clear, width: 1)
            }
            .border(AppConfig.showDebugColors ? Color.purple : Color.clear, width: 1)

            // Row 2: Description (optional)
            if let description = issue.body, !description.isEmpty {
                Text(description)
                    .font(.system(size: 11))
                    .foregroundColor(.bdSecondary)
                    .lineLimit(2)
            }

            // Row 3: Metadata
            HStack(spacing: 8) {
                // Project name (first label)
                if let projectName = issue.projectName {
                    ProjectNameBadge(projectName: projectName)
                }

                // Labels
                if !issue.labels.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(issue.labels.prefix(3), id: \.self) { label in
                            LabelBadge(label: label)
                        }

                        if issue.labels.count > 3 {
                            Text("+\(issue.labels.count - 3)")
                                .font(.system(size: 9))
                                .foregroundColor(.bdSecondary)
                        }
                    }
                }

                // Assignee
                if let assignee = issue.assignee, !assignee.isEmpty {
                    Text("@\(assignee)")
                        .font(.system(size: 9))
                        .foregroundColor(.bdSecondary)
                }

                // External ref
                if let externalRef = issue.externalRef, !externalRef.isEmpty {
                    Text(externalRef)
                        .font(.bdExternalRef)
                        .foregroundColor(.bdSecondary)
                }

                Spacer()

                // Dates
                HStack(spacing: 6) {
                    Text("created \(Date(timeIntervalSince1970: TimeInterval(issue.createdAt)).formatted(.relative(presentation: .named)))")
                        .font(.system(size: 9))
                        .foregroundColor(.bdSecondary)

                    Text("•")
                        .font(.system(size: 9))
                        .foregroundColor(.bdSecondary)

                    Text("updated \(Date(timeIntervalSince1970: TimeInterval(issue.updatedAt)).formatted(.relative(presentation: .named)))")
                        .font(.system(size: 9))
                        .foregroundColor(.bdSecondary)
                }
            }

            // Row 4: Issue ID
            Text(issue.id)
                .font(.bdIssueID)
                .foregroundColor(.secondary.opacity(0.7))
        }
    }
}

// MARK: - Priority Badge

struct PriorityBadge: View {
    let priority: Int

    var body: some View {
        Text("P\(priority)")
            .font(.system(size: 10))
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(priorityColor.opacity(0.2))
            .foregroundColor(priorityColor)
            .cornerRadius(3)
    }

    var priorityColor: Color {
        switch priority {
        case 0: return .red
        case 1: return .orange
        case 2: return .yellow
        case 3: return .blue
        default: return .gray
        }
    }
}

// MARK: - Project Name Badge

struct ProjectNameBadge: View {
    let projectName: String

    var body: some View {
        Text(projectName)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Color.purple.opacity(0.2))
            .foregroundColor(.purple)
            .cornerRadius(3)
    }
}

// MARK: - Label Badge

struct LabelBadge: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 10))
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Color.blue.opacity(0.2))
            .foregroundColor(.blue)
            .cornerRadius(3)
    }
}
