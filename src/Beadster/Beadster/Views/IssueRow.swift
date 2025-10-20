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
        HStack(spacing: 10) {
            // Indentation for tree view
            if depth > 0 {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: CGFloat(depth) * 12)
            }

            // Checkbox
            Button(action: {
                if let project = projectStore.selectedProject {
                    let newStatus = issue.status == "closed" ? "open" : "closed"
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
                        } catch {
                            print("Failed to update issue: \(error)")
                        }
                    }
                }
            }) {
                Image(systemName: issue.status == "closed" ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundColor(issue.status == "closed" ? .green : .gray)
            }
            .buttonStyle(.plain)
            .border(Color.cyan, width: 1) // DEBUG

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
        .padding(.horizontal, 7)
        .padding(.vertical, viewMode == .extended ? 8 : 6)
        .border(Color.yellow, width: 2) // DEBUG
    }

    var simpleView: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Row 1: Title and Priority
            HStack(spacing: 8) {
                Text(issue.title)
                    .font(.system(size: 13))
                    .strikethrough(issue.status == "closed")
                    .lineLimit(1)
                    .border(Color.red, width: 1) // DEBUG

                Spacer()
                    .border(Color.blue, width: 1) // DEBUG

                PriorityBadge(priority: issue.priority)
                    .border(Color.green, width: 1) // DEBUG
            }
            .border(Color.purple, width: 1) // DEBUG

            // Row 2: Description (optional)
            if let description = issue.body, !description.isEmpty {
                Text(description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            // Row 3: Labels
            if !issue.labels.isEmpty {
                HStack(spacing: 4) {
                    ForEach(issue.labels.prefix(3), id: \.self) { label in
                        LabelBadge(label: label)
                    }

                    if issue.labels.count > 3 {
                        Text("+\(issue.labels.count - 3)")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
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
                    .border(Color.red, width: 1) // DEBUG

                Spacer()
                    .border(Color.blue, width: 1) // DEBUG

                PriorityBadge(priority: issue.priority)
                    .border(Color.green, width: 1) // DEBUG
            }
            .border(Color.purple, width: 1) // DEBUG

            // Row 2: Description (optional)
            if let description = issue.body, !description.isEmpty {
                Text(description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            // Row 3: Metadata
            HStack(spacing: 8) {
                // Labels
                if !issue.labels.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(issue.labels.prefix(3), id: \.self) { label in
                            LabelBadge(label: label)
                        }

                        if issue.labels.count > 3 {
                            Text("+\(issue.labels.count - 3)")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()

                // Dates
                HStack(spacing: 6) {
                    Text("created \(Date(timeIntervalSince1970: TimeInterval(issue.createdAt)).formatted(.relative(presentation: .named)))")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)

                    Text("•")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)

                    Text("updated \(Date(timeIntervalSince1970: TimeInterval(issue.updatedAt)).formatted(.relative(presentation: .named)))")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            }

            // Row 4: Issue ID
            Text(issue.id)
                .font(.system(size: 9).monospaced())
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
