//
//  IssueDetailView.swift
//  Beadster
//
//  Created by Anton Podviaznikov on 10/19/25.
//

import SwiftUI

struct IssueDetailView: View {
    let issue: Issue
    @ObservedObject var issueStore: IssueStore
    @Binding var contentMode: ContentMode

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    // ID and status/priority in top right
                    HStack {
                        Text(issue.id)
                            .font(.caption.monospaced())
                            .foregroundColor(.secondary)

                        Spacer()

                        HStack(spacing: 6) {
                            Text(issue.status.capitalized)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(statusColor(issue.status).opacity(0.2))
                                .foregroundColor(statusColor(issue.status))
                                .cornerRadius(4)

                            PriorityBadge(priority: issue.priority)
                        }
                    }

                    // Title
                    Text(issue.title)
                        .font(.title3)
                        .fontWeight(.semibold)

                    // Type and dates
                    HStack(spacing: 8) {
                        if let type = issue.issueType {
                            Text(type.capitalized)
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(4)
                        }

                        Text("Created \(Date(timeIntervalSince1970: TimeInterval(issue.createdAt)).formatted(.relative(presentation: .named)))")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text("Updated \(Date(timeIntervalSince1970: TimeInterval(issue.updatedAt)).formatted(.relative(presentation: .named)))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Labels
                    if !issue.labels.isEmpty {
                        FlowLayout(spacing: 4) {
                            ForEach(issue.labels, id: \.self) { label in
                                LabelBadge(label: label)
                            }
                        }
                    }

                    Divider()

                    // Description
                    if let description = issue.body, !description.isEmpty {
                        Text(description)
                            .font(.body)
                            .textSelection(.enabled)
                    } else {
                        Text("No description")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .italic()
                    }

                    // Dependencies
                    let blockingIssues = issueStore.dependencies.filter { $0.issueId == issue.id }
                    let blockedByIssues = issueStore.dependencies.filter { $0.dependsOnId == issue.id }

                    if !blockingIssues.isEmpty || !blockedByIssues.isEmpty {
                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Dependencies")
                                .font(.headline)
                                .fontWeight(.semibold)

                            // Blocks (what this issue depends on - must be done first)
                            if !blockingIssues.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Blocked by:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    ForEach(blockingIssues, id: \.dependsOnId) { dep in
                                        if let blockingIssue = issueStore.issues.first(where: { $0.id == dep.dependsOnId }) {
                                            Button(action: {
                                                contentMode = .issueDetail(blockingIssue)
                                            }) {
                                                DependencyRow(
                                                    issue: blockingIssue,
                                                    direction: .blockedBy
                                                )
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }

                            // Blocked by (what depends on this issue - waiting for this)
                            if !blockedByIssues.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Blocks:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    ForEach(blockedByIssues, id: \.issueId) { dep in
                                        if let blockedIssue = issueStore.issues.first(where: { $0.id == dep.issueId }) {
                                            Button(action: {
                                                contentMode = .issueDetail(blockedIssue)
                                            }) {
                                                DependencyRow(
                                                    issue: blockedIssue,
                                                    direction: .blocks
                                                )
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
            }
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "open": return .blue
        case "in_progress": return .orange
        case "closed": return .green
        default: return .gray
        }
    }
}

// MARK: - Dependency Row

enum DependencyDirection {
    case blockedBy
    case blocks

    var icon: String {
        switch self {
        case .blockedBy: return "arrow.up.circle.fill"
        case .blocks: return "arrow.down.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .blockedBy: return .orange
        case .blocks: return .blue
        }
    }
}

struct DependencyRow: View {
    let issue: Issue
    let direction: DependencyDirection

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: direction.icon)
                .font(.system(size: 10))
                .foregroundColor(direction.color)

            Text(issue.id)
                .font(.caption.monospaced())
                .foregroundColor(.secondary)

            Text(issue.title)
                .font(.caption)
                .lineLimit(1)

            Spacer()

            Text(issue.status.capitalized)
                .font(.system(size: 9))
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(statusColor(issue.status).opacity(0.2))
                .foregroundColor(statusColor(issue.status))
                .cornerRadius(3)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(6)
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "open": return .blue
        case "in_progress": return .orange
        case "closed": return .green
        default: return .gray
        }
    }
}
