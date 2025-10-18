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
    @State private var showCreateIssue = false
    @State private var editingIssue: Issue?
    @State private var selectedIssue: Issue?

    var body: some View {
        VStack(spacing: 0) {
            if let project = selectedProject {
                // Header
                VStack(spacing: 0) {
                    HStack {
                        Text(project.name)
                            .font(.title2)

                        Spacer()

                        // Create issue button
                        Button(action: {
                            showCreateIssue = true
                        }) {
                            Label("New Issue", systemImage: "plus")
                        }

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
                    List(issueStore.filteredIssues(), selection: $selectedIssue) { issue in
                        IssueRow(issue: issue, issueStore: issueStore)
                            .tag(issue)
                            .contextMenu {
                                Button("View Details") {
                                    selectedIssue = issue
                                }
                                Button("Edit") {
                                    editingIssue = issue
                                }
                                Divider()
                                Button("Delete", role: .destructive) {
                                    Task {
                                        do {
                                            try await issueStore.deleteIssue(projectPath: project.path, issueId: issue.id)
                                            await issueStore.loadIssues(for: project)
                                        } catch {
                                            print("Failed to delete issue: \(error)")
                                        }
                                    }
                                }
                            }
                            .onTapGesture(count: 2) {
                                selectedIssue = issue
                            }
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
        .sheet(isPresented: $showCreateIssue) {
            if let project = selectedProject {
                IssueEditSheet(
                    project: project,
                    issueStore: issueStore,
                    isPresented: $showCreateIssue
                )
            }
        }
        .sheet(item: $editingIssue) { issue in
            if let project = selectedProject {
                IssueEditSheet(
                    project: project,
                    issue: issue,
                    issueStore: issueStore,
                    isPresented: .constant(true),
                    onDismiss: {
                        editingIssue = nil
                    }
                )
            }
        }
        .sheet(item: $selectedIssue) { issue in
            IssueDetailView(issue: issue, onDismiss: {
                selectedIssue = nil
            })
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

                    ForEach(issue.labels, id: \.self) { label in
                        LabelBadge(label: label)
                    }
                }

                Text(issue.title)
                    .font(.body)
                    .strikethrough(issue.status == "closed")

                if let description = issue.body, !description.isEmpty {
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

// MARK: - Issue Detail View

struct IssueDetailView: View {
    let issue: Issue
    var onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Header with ID and status
                    HStack {
                        Text(issue.id)
                            .font(.title3.monospaced())
                            .foregroundColor(.secondary)

                        Spacer()

                        Text(issue.status.capitalized)
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(statusColor(issue.status).opacity(0.2))
                            .foregroundColor(statusColor(issue.status))
                            .cornerRadius(8)
                    }

                    Divider()

                    // Title
                    Text(issue.title)
                        .font(.title2)
                        .fontWeight(.semibold)

                    // Metadata
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Priority", systemImage: "flag.fill")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            PriorityBadge(priority: issue.priority)
                        }

                        HStack {
                            Label("Type", systemImage: "tag.fill")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Text((issue.issueType ?? "task").capitalized)
                                .font(.caption)
                        }

                        HStack {
                            Label("Created", systemImage: "clock.fill")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Text(Date(timeIntervalSince1970: TimeInterval(issue.createdAt)).formatted(.relative(presentation: .named)))
                                .font(.caption)
                        }

                        HStack {
                            Label("Updated", systemImage: "arrow.clockwise")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Text(Date(timeIntervalSince1970: TimeInterval(issue.updatedAt)).formatted(.relative(presentation: .named)))
                                .font(.caption)
                        }

                        if let closedAt = issue.closedAt {
                            HStack {
                                Label("Closed", systemImage: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Text(Date(timeIntervalSince1970: TimeInterval(closedAt)).formatted(.relative(presentation: .named)))
                                    .font(.caption)
                            }
                        }
                    }

                    Divider()

                    // Labels
                    if !issue.labels.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Labels")
                                .font(.headline)

                            FlowLayout(spacing: 4) {
                                ForEach(issue.labels, id: \.self) { label in
                                    LabelBadge(label: label)
                                }
                            }
                        }

                        Divider()
                    }

                    // Description
                    if let description = issue.body, !description.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Description")
                                .font(.headline)

                            Text(description)
                                .font(.body)
                                .textSelection(.enabled)
                        }
                    } else {
                        Text("No description")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle("Issue Details")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDismiss()
                    }
                }
            }
        }
        .frame(width: 600, height: 600)
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

// MARK: - Issue Edit Sheet

struct IssueEditSheet: View {
    let project: ProjectInfo
    var issue: Issue?
    @ObservedObject var issueStore: IssueStore
    @Binding var isPresented: Bool
    var onDismiss: (() -> Void)?

    @State private var title: String
    @State private var description: String
    @State private var priority: Int
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(project: ProjectInfo, issue: Issue? = nil, issueStore: IssueStore, isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil) {
        self.project = project
        self.issue = issue
        self.issueStore = issueStore
        self._isPresented = isPresented
        self.onDismiss = onDismiss

        _title = State(initialValue: issue?.title ?? "")
        _description = State(initialValue: issue?.body ?? "")
        _priority = State(initialValue: issue?.priority ?? 2)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Form {
                    Section("Details") {
                        TextField("Title", text: $title)

                        TextField("Description (optional)", text: $description, axis: .vertical)
                            .lineLimit(5...10)

                        Picker("Priority", selection: $priority) {
                            ForEach(0..<5) { p in
                                Text("P\(p)").tag(p)
                            }
                        }
                    }

                    if let error = errorMessage {
                        Section {
                            Text(error)
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                    }
                }

                Spacer()
            }
            .frame(width: 500, height: 400, alignment: .top)
            .navigationTitle(issue == nil ? "New Issue" : "Edit Issue")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(issue == nil ? "Create" : "Save") {
                        Task {
                            await save()
                        }
                    }
                    .disabled(title.isEmpty || isSaving)
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil

        do {
            if let issue = issue {
                // Update existing issue
                try await issueStore.updateIssue(
                    projectPath: project.path,
                    issueId: issue.id,
                    title: title != issue.title ? title : nil,
                    description: description != issue.body ? description : nil,
                    status: nil,
                    priority: priority != issue.priority ? priority : nil
                )
            } else {
                // Create new issue
                try await issueStore.createIssue(
                    projectPath: project.path,
                    title: title,
                    description: description.isEmpty ? nil : description,
                    priority: priority,
                    labels: []
                )
            }

            // Reload issues
            await issueStore.loadIssues(for: project)

            // Dismiss
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }

        isSaving = false
    }

    private func dismiss() {
        isPresented = false
        onDismiss?()
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
