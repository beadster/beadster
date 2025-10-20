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
        .onAppear {
            // Check if we have projects
            if !projectStore.projects.isEmpty {
                // Load issues from ALL projects
                Task { @MainActor in
                    await issueStore.loadIssuesFromAllProjects(projects: projectStore.projects)
                    contentMode = .issuesList
                }
            } else {
                // Show onboarding
                contentMode = .onboarding
            }
        }
        .onChange(of: projectStore.projects.count) { oldCount, newCount in
            // When projects change, reload all issues
            if newCount > 0 {
                Task { @MainActor in
                    await issueStore.loadIssuesFromAllProjects(projects: projectStore.projects)
                    if contentMode == .onboarding {
                        contentMode = .issuesList
                    }
                }
            } else {
                contentMode = .onboarding
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

                // Move window buttons 2 pixels to the right
                if let closeButton = window.standardWindowButton(.closeButton) {
                    closeButton.alphaValue = alpha
                    var frame = closeButton.frame
                    frame.origin.x += 2
                    closeButton.setFrameOrigin(frame.origin)
                }
                if let miniButton = window.standardWindowButton(.miniaturizeButton) {
                    miniButton.alphaValue = alpha
                    var frame = miniButton.frame
                    frame.origin.x += 2
                    miniButton.setFrameOrigin(frame.origin)
                }
                if let zoomButton = window.standardWindowButton(.zoomButton) {
                    zoomButton.alphaValue = alpha
                    var frame = zoomButton.frame
                    frame.origin.x += 2
                    zoomButton.setFrameOrigin(frame.origin)
                }

                // Set window level based on pin state
                window.level = isPinned ? .floating : .normal
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let window = nsView.window {
            let alpha: CGFloat = alwaysShow ? 1.0 : (isHovering ? 1 : 0)

            // Move window buttons 2 pixels to the right and update alpha
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2

                if let closeButton = window.standardWindowButton(.closeButton) {
                    closeButton.animator().alphaValue = alpha
                    var frame = closeButton.frame
                    frame.origin.x = 10  // 8 (default) + 2
                    closeButton.setFrameOrigin(frame.origin)
                }
                if let miniButton = window.standardWindowButton(.miniaturizeButton) {
                    miniButton.animator().alphaValue = alpha
                    var frame = miniButton.frame
                    frame.origin.x = 30  // 28 (default) + 2
                    miniButton.setFrameOrigin(frame.origin)
                }
                if let zoomButton = window.standardWindowButton(.zoomButton) {
                    zoomButton.animator().alphaValue = alpha
                    var frame = zoomButton.frame
                    frame.origin.x = 50  // 48 (default) + 2
                    zoomButton.setFrameOrigin(frame.origin)
                }
            }

            // Update window level when pin state changes
            window.level = isPinned ? .floating : .normal
        }
    }
}

#Preview {
    MainView()
}
