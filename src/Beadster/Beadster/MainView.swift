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
    @State private var showFilters = false

    var body: some View {
        VStack(spacing: 0) {
            if let project = selectedProject {
                // Header
                VStack(spacing: 0) {
                    HStack {
                        Text(project.name)
                            .font(.title2)

                        Spacer()

                        // Status filter
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

                    // Search bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)

                        TextField("Search issues...", text: $issueStore.searchText)
                            .textFieldStyle(.plain)

                        if !issueStore.searchText.isEmpty {
                            Button(action: {
                                issueStore.searchText = ""
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }

                        Button(action: {
                            showFilters.toggle()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "line.3.horizontal.decrease.circle")
                                if issueStore.selectedPriority != nil || !issueStore.selectedLabels.isEmpty {
                                    Image(systemName: "circle.fill")
                                        .font(.system(size: 6))
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .help("Advanced filters")
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)

                    // Advanced filters (when expanded)
                    if showFilters {
                        VStack(alignment: .leading, spacing: 8) {
                            // Priority filter
                            HStack {
                                Text("Priority:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                ForEach(0..<5) { priority in
                                    Button(action: {
                                        if issueStore.selectedPriority == priority {
                                            issueStore.selectedPriority = nil
                                        } else {
                                            issueStore.selectedPriority = priority
                                        }
                                    }) {
                                        Text("P\(priority)")
                                            .font(.caption)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(issueStore.selectedPriority == priority ? Color.blue : Color.gray.opacity(0.2))
                                            .foregroundColor(issueStore.selectedPriority == priority ? .white : .primary)
                                            .cornerRadius(4)
                                    }
                                    .buttonStyle(.plain)
                                }

                                Spacer()
                            }

                            // Label filter
                            if !issueStore.allLabels().isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Labels:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    FlowLayout(spacing: 4) {
                                        ForEach(issueStore.allLabels(), id: \.self) { label in
                                            Button(action: {
                                                if issueStore.selectedLabels.contains(label) {
                                                    issueStore.selectedLabels.remove(label)
                                                } else {
                                                    issueStore.selectedLabels.insert(label)
                                                }
                                            }) {
                                                Text(label)
                                                    .font(.caption)
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 4)
                                                    .background(issueStore.selectedLabels.contains(label) ? Color.blue : Color.gray.opacity(0.2))
                                                    .foregroundColor(issueStore.selectedLabels.contains(label) ? .white : .primary)
                                                    .cornerRadius(4)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }

                            // Clear filters button
                            if issueStore.selectedPriority != nil || !issueStore.selectedLabels.isEmpty {
                                Button("Clear Filters") {
                                    issueStore.clearFilters()
                                }
                                .font(.caption)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                    }
                }

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

// MARK: - FlowLayout Helper

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeViews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeViews(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrangeViews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        let proposalWidth = proposal.width ?? .infinity

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > proposalWidth && currentX > 0 {
                // Move to next line
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            maxWidth = max(maxWidth, currentX)
        }

        return (CGSize(width: maxWidth, height: currentY + lineHeight), positions)
    }
}

#Preview {
    MainView()
}
