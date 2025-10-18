//
//  MainView.swift
//  Beadster
//
//  Created by Anton Podviaznikov on 10/18/25.
//

import SwiftUI

struct MainView: View {
    @StateObject private var projectStore = ProjectStore()
    @StateObject private var issueStore = IssueStore()

    var body: some View {
        NavigationSplitView {
            // Sidebar: Projects
            ProjectsSidebar(
                projectStore: projectStore,
                issueStore: issueStore
            )
        } detail: {
            // Main content: Issues
            IssuesListView(
                issueStore: issueStore,
                selectedProject: projectStore.selectedProject
            )
        }
        .frame(minWidth: 900, minHeight: 600)
    }
}

// MARK: - Projects Sidebar

struct ProjectsSidebar: View {
    @ObservedObject var projectStore: ProjectStore
    @ObservedObject var issueStore: IssueStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Projects")
                .font(.headline)
                .padding()

            if let error = projectStore.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }

            if projectStore.isScanning {
                ProgressView("Scanning...")
                    .padding()
            }

            List(projectStore.projects, selection: $projectStore.selectedProject) { project in
                ProjectRow(project: project)
                    .tag(project)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Button(action: {
                    print("UI: Add Projects button clicked")
                    projectStore.selectFolderToScan()
                }) {
                    Label("Add Projects", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.plain)

                Button(action: {
                    print("UI: Add Claude Logs button clicked")
                    selectClaudeLogs()
                }) {
                    Label("Add Claude Logs", systemImage: "doc.text.magnifyingglass")
                }
                .buttonStyle(.plain)
            }
            .padding()
        }
        .frame(minWidth: 200)
        .onChange(of: projectStore.selectedProject) { oldValue, newValue in
            if let project = newValue {
                Task { @MainActor in
                    await issueStore.loadIssues(for: project)
                }
            }
        }
    }

    func selectClaudeLogs() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select your .claude folder for context capture"
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")

        if panel.runModal() == .OK, let url = panel.url {
            print("Selected Claude folder: \(url.path)")
            // TODO: save bookmark for Claude folder
        }
    }
}

struct ProjectRow: View {
    let project: ProjectInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(project.name)
                .font(.body)

            Text(project.path)
                .font(.caption)
                .foregroundColor(.secondary)

            if let lastSync = project.lastSync {
                Text("Synced \(lastSync.formatted(.relative(presentation: .named)))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Issues List

struct IssuesListView: View {
    @ObservedObject var issueStore: IssueStore
    let selectedProject: ProjectInfo?

    var body: some View {
        VStack {
            if let project = selectedProject {
                // Header
                HStack {
                    Text(project.name)
                        .font(.title2)

                    Spacer()

                    Picker("Filter", selection: $issueStore.filter) {
                        ForEach(IssueFilter.allCases, id: \.self) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 250)

                    Text("\(issueStore.filteredIssues().count) issues")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()

                Divider()

                // Issues list
                if issueStore.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if issueStore.filteredIssues().isEmpty {
                    ContentUnavailableView(
                        "No Issues",
                        systemImage: "checklist",
                        description: Text("No issues found for this project")
                    )
                } else {
                    List(issueStore.filteredIssues()) { issue in
                        IssueRow(issue: issue, issueStore: issueStore)
                    }
                }
            } else {
                // No project selected
                ContentUnavailableView(
                    "No Project Selected",
                    systemImage: "folder.badge.questionmark",
                    description: Text("Select a project from the sidebar or add a new one")
                )
            }
        }
    }
}

struct IssueRow: View {
    let issue: Issue
    @ObservedObject var issueStore: IssueStore

    var body: some View {
        HStack(spacing: 12) {
            // Checkbox
            Button(action: {
                issueStore.toggleIssueStatus(issue)
            }) {
                Image(systemName: issue.status == "closed" ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(issue.status == "closed" ? .green : .gray)
            }
            .buttonStyle(.plain)

            // Content
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(issue.id)
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)

                    PriorityBadge(priority: issue.priority)

                    if let labels = issue.labels {
                        ForEach(labels, id: \.self) { label in
                            LabelBadge(label: label)
                        }
                    }
                }

                Text(issue.title)
                    .font(.body)
                    .strikethrough(issue.status == "closed")

                if let description = issue.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct PriorityBadge: View {
    let priority: Int

    var body: some View {
        Text("P\(priority)")
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(priorityColor.opacity(0.2))
            .foregroundColor(priorityColor)
            .cornerRadius(4)
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

struct LabelBadge: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.blue.opacity(0.2))
            .foregroundColor(.blue)
            .cornerRadius(4)
    }
}

#Preview {
    MainView()
}
