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
                            .font(.bdIssueID)
                            .foregroundColor(.secondary)

                        Spacer()

                        HStack(spacing: 6) {
                            Text(formatLabel(issue.status))
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
                            Text(formatLabel(type))
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(4)
                        }

                        Text("created \(Date(timeIntervalSince1970: TimeInterval(issue.createdAt)).formatted(.relative(presentation: .named)))")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text("updated \(Date(timeIntervalSince1970: TimeInterval(issue.updatedAt)).formatted(.relative(presentation: .named)))")
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

                    // Metadata section
                    VStack(alignment: .leading, spacing: 8) {
                        if let assignee = issue.assignee, !assignee.isEmpty {
                            HStack {
                                Text("Assignee:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(assignee)
                                    .font(.caption)
                            }
                        }

                        if let externalRef = issue.externalRef, !externalRef.isEmpty {
                            HStack {
                                Text("External Ref:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(externalRef)
                                    .font(.bdExternalRef)
                            }
                        }

                        if let estimatedMinutes = issue.estimatedMinutes {
                            HStack {
                                Text("Estimated:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("\(estimatedMinutes) min")
                                    .font(.caption)
                            }
                        }

                        if let closedAt = issue.closedAt {
                            HStack {
                                Text("Closed:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(Date(timeIntervalSince1970: TimeInterval(closedAt)).formatted(.relative(presentation: .named)))
                                    .font(.caption)
                            }
                        }
                    }

                    // Description
                    if let description = issue.body, !description.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Description")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(description)
                                .font(.body)
                                .textSelection(.enabled)
                        }
                    }

                    // Design
                    if let design = issue.design, !design.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Design")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(design)
                                .font(.body)
                                .textSelection(.enabled)
                        }
                    }

                    // Acceptance Criteria
                    if let acceptanceCriteria = issue.acceptanceCriteria, !acceptanceCriteria.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Acceptance Criteria")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(acceptanceCriteria)
                                .font(.body)
                                .textSelection(.enabled)
                        }
                    }

                    // Notes
                    if let notes = issue.notes, !notes.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Notes")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(notes)
                                .font(.body)
                                .textSelection(.enabled)
                        }
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

    private func formatLabel(_ text: String) -> String {
        return text.replacingOccurrences(of: "_", with: " ").lowercased()
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
                .font(.bdIssueID)
                .foregroundColor(.secondary)

            Text(issue.title)
                .font(.caption)
                .lineLimit(1)

            Spacer()

            Text(formatLabel(issue.status))
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

    private func formatLabel(_ text: String) -> String {
        return text.replacingOccurrences(of: "_", with: " ").lowercased()
    }
}
