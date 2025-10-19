//
//  MainView.swift
//  Beadster
//
//  Created by Anton Podviaznikov on 10/18/25.
//

import SwiftUI
import AppKit

// MARK: - Layout Constants

private enum LayoutConstants {
    static let appHeaderHeight: CGFloat = 28
    static let contentHeaderHeight: CGFloat = 48
    static let footerHeight: CGFloat = 24
}

// MARK: - App State

enum AppTab: String, CaseIterable {
    case projects = "Projects"
    case openIssues = "Open"
    case allIssues = "All"
    case closedIssues = "Closed"
}

enum ViewMode: String, CaseIterable, RawRepresentable {
    case simple = "simple"
    case extended = "extended"
    case tree = "tree"

    var displayName: String {
        switch self {
        case .simple: return "Simple"
        case .extended: return "Extended"
        case .tree: return "Tree"
        }
    }
}

enum ContentMode: Equatable {
    case onboarding
    case projectsList
    case issuesList
    case issueDetail(Issue)
    case settings
}

// MARK: - Main View

struct MainView: View {
    @StateObject private var projectStore = ProjectStore()
    @StateObject private var issueStore = IssueStore()
    @StateObject private var syncDaemon = SyncDaemon.shared

    @State private var isHoveringWindow = false
    @State private var isHoveringHeader = false
    @State private var isHoveringFooter = false
    @State private var selectedTab: AppTab = .openIssues
    @State private var contentMode: ContentMode = .onboarding
    @State private var showSearch = false
    @AppStorage("isPinned") private var isPinned = false
    @AppStorage("viewMode") private var viewMode: ViewMode = .simple
    @FocusState private var isSearchFocused: Bool
    @State private var copiedProjectId: String?

    var body: some View {
        VStack(spacing: 0) {
            // App Header (titlebar)
            appHeader

            // Content Header (only show for non-settings)
            if case .settings = contentMode {
                // No header for settings
            } else {
                contentHeader
                Divider()
            }

            // Content Area (takes remaining space)
            contentArea
                .frame(maxHeight: .infinity)

            if case .settings = contentMode {
                // No divider for settings
            } else {
                Divider()
            }

            // Footer
            footer
                .frame(height: LayoutConstants.footerHeight)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
        .background(WindowAccessor(isHovering: $isHoveringWindow, alwaysShow: true, isPinned: $isPinned))
        .edgesIgnoringSafeArea(.top)
        .onChange(of: projectStore.selectedProject) { oldValue, newValue in
            if let project = newValue {
                Task { @MainActor in
                    await issueStore.loadIssues(for: project)
                    if !issueStore.filteredIssues().isEmpty {
                        contentMode = .issuesList
                    }
                }
            }
        }
        .onAppear {
            // Check if we have projects
            if !projectStore.projects.isEmpty {
                // Select first project
                projectStore.selectedProject = projectStore.projects.first
                contentMode = .issuesList
            } else {
                // Show onboarding
                contentMode = .onboarding
            }
        }
        .onChange(of: projectStore.projects.count) { oldCount, newCount in
            // When first project is added, select it and switch to issues list
            if newCount > 0 && contentMode == .onboarding {
                Task { @MainActor in
                    projectStore.selectedProject = projectStore.projects.first
                    contentMode = .issuesList
                }
            }
        }
    }

    // MARK: - App Header

    var appHeader: some View {
        HStack(spacing: 8) {
            Spacer()

            Button(action: {
                print("⚙️  Gear icon clicked! Current mode: \(contentMode)")
                contentMode = .settings
                print("⚙️  Changed to settings mode")
            }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .foregroundColor(.black.opacity(0.6))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .background(Color.purple.opacity(0.5)) // DEBUG
            .border(Color.purple, width: 2) // DEBUG

            Button(action: {
                isPinned.toggle()
                print("📌 Pin clicked!")
            }) {
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 13))
                    .foregroundColor(.black.opacity(0.6))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .background(Color.orange.opacity(0.5)) // DEBUG
            .border(Color.orange, width: 2) // DEBUG
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 0)
        .frame(height: LayoutConstants.appHeaderHeight)
        .background(Color.red.opacity(0.3)) // DEBUG
        .border(Color.red, width: 2) // DEBUG
        .overlay(
            Text("H:\(LayoutConstants.appHeaderHeight)")
                .font(.system(size: 8))
                .foregroundColor(.black)
                .position(x: 200, y: 14)
        )
        .allowsHitTesting(true) // DEBUG: ensure hit testing is enabled
        .zIndex(100) // DEBUG: bring to front
        // TODO: Restore hover behavior after layout is working
//        .onHover { hovering in
//            withAnimation(.easeInOut(duration: 0.2)) {
//                isHoveringHeader = hovering
//                isHoveringWindow = hovering
//            }
//        }
//        .opacity(isHoveringHeader ? 1 : 0)
    }

    // MARK: - Content Header

    var contentHeader: some View {
        Group {
            if case .settings = contentMode {
                // Settings has its own header, hide this one
                EmptyView()
                    .frame(height: 0)
            } else if case .issueDetail(let issue) = contentMode {
                // Issue detail header
                issueDetailHeader(issue: issue)
            } else {
                // Default header with search and tabs
                issuesListHeader
            }
        }
    }

    var issuesListHeader: some View {
        HStack(spacing: 8) {
            // Search button or search input
            if showSearch {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)

                    TextField("Search...", text: $issueStore.searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .focused($isSearchFocused)

                    Button(action: {
                        showSearch = false
                        issueStore.searchText = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(6)
                .frame(width: 140)
                .onAppear {
                    isSearchFocused = true
                }
            } else {
                Button(action: {
                    showSearch = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isSearchFocused = true
                    }
                }) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13))
                        .foregroundColor(.black.opacity(0.6))
                }
                .buttonStyle(.plain)
            }

            Spacer()

            // Filter Tabs (Projects, Open, All, Closed)
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button(action: {
                    selectedTab = tab
                    if tab == .projects {
                        contentMode = .projectsList
                    } else {
                        // Update filter based on tab
                        switch tab {
                        case .openIssues:
                            issueStore.filter = .open
                        case .allIssues:
                            issueStore.filter = .all
                        case .closedIssues:
                            issueStore.filter = .closed
                        case .projects:
                            break
                        }
                        // Always switch to issues list when changing filter tabs
                        contentMode = .issuesList
                    }
                }) {
                    Text(tab.rawValue)
                        .font(.system(size: 11))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(selectedTab == tab ? Color.blue.opacity(0.2) : Color.clear)
                        .foregroundColor(selectedTab == tab ? .blue : .black.opacity(0.6))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }

            // Divider
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 1, height: 20)
                .padding(.horizontal, 4)

            // View Mode Tabs (Simple, Extended, Tree)
            ForEach(ViewMode.allCases, id: \.self) { mode in
                Button(action: {
                    viewMode = mode
                }) {
                    Text(mode.displayName)
                        .font(.system(size: 11))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(viewMode == mode ? Color.blue.opacity(0.2) : Color.clear)
                        .foregroundColor(viewMode == mode ? .blue : .black.opacity(0.6))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: LayoutConstants.contentHeaderHeight)
        .background(Color.green.opacity(0.3)) // DEBUG
        .border(Color.green, width: 2) // DEBUG
    }

    func issueDetailHeader(issue: Issue) -> some View {
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
                print("MainView: Done/Reopen button tapped for issue \(issue.id)")
                if let project = projectStore.selectedProject {
                    let newStatus = issue.status == "closed" ? "open" : "closed"
                    print("MainView: Changing status from '\(issue.status)' to '\(newStatus)'")
                    print("MainView: Project path: \(project.path)")
                    Task {
                        do {
                            // Write to JSONL to persist the change
                            print("MainView: Calling updateIssue...")
                            try await issueStore.updateIssue(
                                projectPath: project.path,
                                issueId: issue.id,
                                title: nil,
                                description: nil,
                                status: newStatus,
                                priority: nil
                            )
                            print("MainView: updateIssue completed, reloading issues...")
                            // Reload issues from the updated JSONL
                            await issueStore.loadIssues(for: project)
                            print("MainView: Issues reloaded")
                            // Update view with the refreshed issue
                            if let updatedIssue = issueStore.issues.first(where: { $0.id == issue.id }) {
                                print("MainView: Updating contentMode with refreshed issue")
                                contentMode = .issueDetail(updatedIssue)
                            }
                        } catch {
                            print("MainView: ERROR - Failed to update issue status: \(error)")
                        }
                    }
                } else {
                    print("MainView: ERROR - No project selected!")
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
        .background(Color.green.opacity(0.3)) // DEBUG
        .border(Color.green, width: 2) // DEBUG
    }

    // MARK: - Content Area

    var contentArea: some View {
        Group {
            switch contentMode {
            case .onboarding:
                onboardingView
            case .projectsList:
                projectsListView
            case .issuesList:
                issuesListView
            case .issueDetail(let issue):
                issueDetailView(issue: issue)
            case .settings:
                settingsView
            }
        }
    }

    // MARK: - Projects List View

    var projectsListView: some View {
        VStack(spacing: 0) {
            if projectStore.projects.isEmpty {
                VStack(spacing: 20) {
                    Text("No projects connected")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.black.opacity(0.9))

                    Button(action: {
                        projectStore.selectFolderToScan()
                    }) {
                        HStack {
                            Image(systemName: "folder.badge.plus")
                            Text("Add Projects")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal, 40)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(projectStore.projects) { project in
                            HStack(spacing: 10) {
                                // Project icon
                                Image(systemName: "folder.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(.blue)

                                // Project info
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(project.name)
                                            .font(.system(size: 13))

                                        if let sourceId = project.sourceId {
                                            Text(sourceId)
                                                .font(.system(size: 10).monospaced())
                                                .foregroundColor(.secondary)
                                        }
                                    }

                                    if let lastSync = project.lastSync {
                                        Text("Synced \(lastSync.formatted(.relative(presentation: .named)))")
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                    }
                                }

                                Spacer()

                                // Actions
                                HStack(spacing: 8) {
                                    Button(action: {
                                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: project.path)
                                    }) {
                                        Image(systemName: "folder")
                                            .font(.system(size: 12))
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Open in Finder")

                                    Button(action: {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(project.path, forType: .string)
                                        copiedProjectId = project.id

                                        // Clear after 3 seconds
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                            if copiedProjectId == project.id {
                                                copiedProjectId = nil
                                            }
                                        }
                                    }) {
                                        Image(systemName: copiedProjectId == project.id ? "checkmark" : "doc.on.doc")
                                            .font(.system(size: 12))
                                            .foregroundColor(copiedProjectId == project.id ? .green : .secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .help(copiedProjectId == project.id ? "Copied!" : "Copy path")
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                            .contextMenu {
                                Button("Remove", role: .destructive) {
                                    projectStore.removeProject(project)
                                }
                            }

                            Divider()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Onboarding View

    var onboardingView: some View {
        VStack(spacing: 20) {
            Text("Welcome to Beadster")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.black.opacity(0.9))

            Text("Get started by connecting your projects")
                .font(.system(size: 13))
                .foregroundColor(.black.opacity(0.6))
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                Button(action: {
                    projectStore.selectFolderToScan()
                }) {
                    HStack {
                        Image(systemName: "folder.badge.plus")
                        Text("Connect Project Folders")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button(action: {
                    selectClaudeLogs()
                }) {
                    HStack {
                        Image(systemName: "doc.text.magnifyingglass")
                        Text("Connect Claude Logs")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 40)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Issues List View

    var issuesListView: some View {
        ScrollView {
            VStack(spacing: 0) {
                if issueStore.isLoading {
                    ProgressView()
                        .padding()
                } else if issueStore.filteredIssues().isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "checklist")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)
                        Text("No Issues")
                            .font(.headline)

                        if let project = projectStore.selectedProject {
                            Button(action: {
                                // TODO: Create new issue
                            }) {
                                Label("Create Issue", systemImage: "plus")
                            }
                        }
                    }
                    .padding()
                } else {
                    ForEach(issueStore.filteredIssues()) { issue in
                        IssueRowCompact(issue: issue, issueStore: issueStore, viewMode: viewMode)
                            .environmentObject(projectStore)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                contentMode = .issueDetail(issue)
                            }

                        Divider()
                    }
                }
            }
        }
    }

    // MARK: - Issue Detail View

    func issueDetailView(issue: Issue) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    // ID and status
                    HStack {
                        Text(issue.id)
                            .font(.caption.monospaced())
                            .foregroundColor(.secondary)

                        Spacer()

                        Text(issue.status.capitalized)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(statusColor(issue.status).opacity(0.2))
                            .foregroundColor(statusColor(issue.status))
                            .cornerRadius(4)
                    }

                    // Title
                    Text(issue.title)
                        .font(.title3)
                        .fontWeight(.semibold)

                    // Metadata
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            PriorityBadge(priority: issue.priority)

                            if let type = issue.issueType {
                                Text(type.capitalized)
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.gray.opacity(0.2))
                                    .cornerRadius(4)
                            }
                        }

                        Text("Created \(Date(timeIntervalSince1970: TimeInterval(issue.createdAt)).formatted(.relative(presentation: .named)))")
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
                }
                .padding(.horizontal, 12)
            }
        }
    }

    // MARK: - Footer

    var footer: some View {
        HStack(spacing: 12) {
            // Left side: Cloud sync status
            HStack(spacing: 6) {
                if syncDaemon.isSyncing {
                    // Syncing badge
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 10, height: 10)
                        Text("Syncing")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.15))
                    .foregroundColor(.blue)
                    .cornerRadius(3)

                    if let issueId = syncDaemon.currentSyncingIssueId {
                        Text("issue \(issueId)")
                            .font(.system(size: 9))
                            .foregroundColor(.black.opacity(0.6))
                    } else {
                        Text("cloud")
                            .font(.system(size: 9))
                            .foregroundColor(.black.opacity(0.6))
                    }
                } else if let error = syncDaemon.syncError {
                    // Error badge
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 8))
                        Text("Error")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.15))
                    .foregroundColor(.orange)
                    .cornerRadius(3)

                    Text(error)
                        .font(.system(size: 9))
                        .foregroundColor(.black.opacity(0.6))
                        .lineLimit(1)
                        .truncationMode(.tail)
                } else if let lastSync = syncDaemon.lastSyncDate {
                    // Synced badge
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 8))
                        Text("Synced")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.15))
                    .foregroundColor(.green)
                    .cornerRadius(3)

                    Text("\(lastSync.formatted(.relative(presentation: .named)))")
                        .font(.system(size: 9))
                        .foregroundColor(.black.opacity(0.6))
                } else {
                    // No sync yet
                    HStack(spacing: 4) {
                        Image(systemName: "cloud")
                            .font(.system(size: 8))
                        Text("Not synced")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.gray.opacity(0.15))
                    .foregroundColor(.gray)
                    .cornerRadius(3)
                }
            }

            Spacer()

            // Right side: Local sync status
            HStack(spacing: 6) {
                if syncDaemon.watchedProjectsCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                            .font(.system(size: 8))
                        Text("Watching")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.15))
                    .foregroundColor(.blue)
                    .cornerRadius(3)

                    Text("\(syncDaemon.watchedProjectsCount) project\(syncDaemon.watchedProjectsCount == 1 ? "" : "s")")
                        .font(.system(size: 9))
                        .foregroundColor(.black.opacity(0.6))

                    if let lastChange = syncDaemon.lastLocalChangeDate {
                        Text("• changed \(lastChange.formatted(.relative(presentation: .named)))")
                            .font(.system(size: 9))
                            .foregroundColor(.black.opacity(0.5))
                    }
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                            .font(.system(size: 8))
                        Text("No projects")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.gray.opacity(0.15))
                    .foregroundColor(.gray)
                    .cornerRadius(3)
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: LayoutConstants.footerHeight)
        .background(Color.yellow.opacity(0.3)) // DEBUG
        .border(Color.yellow, width: 2) // DEBUG
        // TODO: Restore hover behavior after layout is working
//        .opacity(isHoveringFooter ? 1 : 0)
//        .onHover { hovering in
//            withAnimation(.easeInOut(duration: 0.2)) {
//                isHoveringFooter = hovering
//            }
//        }
    }

    // MARK: - Settings View

    var settingsView: some View {
        SettingsView(
            projectStore: projectStore,
            syncDaemon: syncDaemon,
            onClose: {
                contentMode = .issuesList
            }
        )
    }

    // MARK: - Helpers

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

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "open": return .blue
        case "in_progress": return .orange
        case "closed": return .green
        default: return .gray
        }
    }
}

// MARK: - Compact Issue Row

struct IssueRowCompact: View {
    let issue: Issue
    @ObservedObject var issueStore: IssueStore
    let viewMode: ViewMode
    @EnvironmentObject var projectStore: ProjectStore

    var body: some View {
        HStack(spacing: 10) {
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

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, viewMode == .extended ? 8 : 6)
    }

    var simpleView: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Row 1: Title and Priority
            HStack(spacing: 8) {
                Text(issue.title)
                    .font(.system(size: 13))
                    .strikethrough(issue.status == "closed")
                    .lineLimit(1)

                Spacer()

                PriorityBadge(priority: issue.priority)
            }

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

                Spacer()

                PriorityBadge(priority: issue.priority)
            }

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

// MARK: - Flow Layout

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

// MARK: - Window Accessor

struct WindowAccessor: NSViewRepresentable {
    @Binding var isHovering: Bool
    var alwaysShow: Bool = false
    @Binding var isPinned: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                window.titlebarAppearsTransparent = true
                let alpha: CGFloat = alwaysShow ? 1.0 : (isHovering ? 1 : 0)
                window.standardWindowButton(.closeButton)?.alphaValue = alpha
                window.standardWindowButton(.miniaturizeButton)?.alphaValue = alpha
                window.standardWindowButton(.zoomButton)?.alphaValue = alpha

                // Set window level based on pin state
                window.level = isPinned ? .floating : .normal
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let window = nsView.window {
            let alpha: CGFloat = alwaysShow ? 1.0 : (isHovering ? 1 : 0)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                window.standardWindowButton(.closeButton)?.animator().alphaValue = alpha
                window.standardWindowButton(.miniaturizeButton)?.animator().alphaValue = alpha
                window.standardWindowButton(.zoomButton)?.animator().alphaValue = alpha
            }

            // Update window level when pin state changes
            window.level = isPinned ? .floating : .normal
        }
    }
}

#Preview {
    MainView()
}
