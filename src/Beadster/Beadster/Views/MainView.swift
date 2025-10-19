//
//  MainView.swift
//  Beadster
//
//  Created by Anton Podviaznikov on 10/18/25.
//

import SwiftUI
import AppKit

// MARK: - Main View

struct MainView: View {
    @StateObject private var projectStore = ProjectStore()
    @StateObject private var issueStore = IssueStore()
    @StateObject private var syncDaemon = SyncDaemon.shared

    @State private var isHoveringWindow = false
    @State private var selectedTab: AppTab = .openIssues
    @State private var contentMode: ContentMode = .onboarding
    @State private var showSearch = false
    @AppStorage("isPinned") private var isPinned = false
    @AppStorage("viewMode") private var viewMode: ViewMode = .simple
    @FocusState private var isSearchFocused: Bool
    @State private var copiedProjectId: String?
    @State private var selectedIssueIndex: Int = 0
    @State private var selectedProjectIndex: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            // App Header (titlebar)
            AppHeader(contentMode: $contentMode, isPinned: $isPinned)

            // Content Header (only show for non-settings)
            if case .settings = contentMode {
                // No header for settings
            } else {
                ContentHeader(
                    contentMode: $contentMode,
                    selectedTab: $selectedTab,
                    viewMode: $viewMode,
                    showSearch: $showSearch,
                    issueStore: issueStore,
                    projectStore: projectStore,
                    isSearchFocused: $isSearchFocused
                )
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
            AppFooter(syncDaemon: syncDaemon)
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

    // MARK: - Content Area

    var contentArea: some View {
        Group {
            switch contentMode {
            case .onboarding:
                OnboardingView(projectStore: projectStore)
            case .projectsList:
                ProjectsListView(
                    projectStore: projectStore,
                    selectedProjectIndex: $selectedProjectIndex,
                    copiedProjectId: $copiedProjectId,
                    selectedTab: $selectedTab,
                    contentMode: $contentMode,
                    issueStore: issueStore
                )
            case .issuesList:
                IssuesListView(
                    issueStore: issueStore,
                    selectedIssueIndex: $selectedIssueIndex,
                    contentMode: $contentMode,
                    viewMode: viewMode
                )
                .environmentObject(projectStore)
            case .issueDetail(let issue):
                IssueDetailView(issue: issue, issueStore: issueStore, contentMode: $contentMode)
            case .settings:
                SettingsView(
                    projectStore: projectStore,
                    syncDaemon: syncDaemon,
                    onClose: {
                        contentMode = .issuesList
                    }
                )
            }
        }
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
