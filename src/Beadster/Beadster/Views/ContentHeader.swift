//
//  ContentHeader.swift
//  Beadster
//
//  Created by Anton Podviaznikov on 10/19/25.
//

import SwiftUI

struct ContentHeader: View {
    @Binding var contentMode: ContentMode
    @Binding var selectedTab: AppTab
    @Binding var viewMode: ViewMode
    @Binding var showSearch: Bool
    @ObservedObject var issueStore: IssueStore
    @ObservedObject var projectStore: ProjectStore
    @FocusState.Binding var isSearchFocused: Bool

    var body: some View {
        Group {
            if case .settings = contentMode {
                // Settings header
                settingsHeader
            } else if case .newIssue = contentMode {
                // New issue header
                newIssueHeader
            } else if case .issueDetail(let issue) = contentMode {
                // Issue detail header
                IssueDetailHeader(
                    issue: issue,
                    issueStore: issueStore,
                    projectStore: projectStore,
                    contentMode: $contentMode
                )
            } else {
                // Default header with search and tabs
                issuesListHeader
            }
        }
    }

    var issuesListHeader: some View {
        ZStack {
            // Main header content
            HStack(spacing: 8) {
                // Search button (when not active)
                if !showSearch {
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

                // Status Filter Tabs (Open, All, Closed)
                ForEach(AppTab.allCases, id: \.self) { tab in
                    Button(action: {
                        selectedTab = tab
                        // Update filter based on tab
                        switch tab {
                        case .openIssues:
                            issueStore.filter = .open
                        case .allIssues:
                            issueStore.filter = .all
                        case .closedIssues:
                            issueStore.filter = .closed
                        }
                        // Always switch to issues list when changing filter tabs
                        contentMode = .issuesList
                    }) {
                        Text(tab.rawValue)
                            .font(.system(size: 11))
                            .padding(.horizontal, 4)
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

                // Project Filter Dropdown
                Menu {
                    Button("All") {
                        issueStore.selectedProjectId = nil
                    }
                    Divider()
                    ForEach(projectStore.projects, id: \.id) { project in
                        Button(project.name) {
                            issueStore.selectedProjectId = project.name
                        }
                    }
                } label: {
                    Text(issueStore.selectedProjectId ?? "All")
                        .font(.system(size: 11))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 4)
                        .foregroundColor(.black.opacity(0.6))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

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
                        Image(systemName: mode.symbolName)
                            .font(.system(size: 13))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 3)
                            .background(viewMode == mode ? Color.blue.opacity(0.2) : Color.clear)
                            .foregroundColor(viewMode == mode ? .blue : .black.opacity(0.6))
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .help(mode.displayName)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: LayoutConstants.contentHeaderHeight)
            .background(AppConfig.showDebugColors ? Color.green.opacity(0.3) : Color.clear)
            .border(AppConfig.showDebugColors ? Color.green : Color.clear, width: 2)

            // Search overlay (full width)
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
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.white)
                .cornerRadius(6)
                .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                .padding(.horizontal, 10)
                .onAppear {
                    isSearchFocused = true
                }
            }
        }
    }

    var settingsHeader: some View {
        HStack {
            Text("Settings")
                .font(.headline)
            Spacer()
            Button(action: {
                contentMode = .issuesList
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .frame(height: LayoutConstants.contentHeaderHeight)
    }

    var newIssueHeader: some View {
        HStack {
            Button(action: {
                contentMode = .issuesList
            }) {
                Text("Cancel")
                    .font(.body)
            }
            .buttonStyle(.plain)

            Spacer()

            Text("New Issue")
                .font(.headline)

            Spacer()

            Button(action: {
                NotificationCenter.default.post(name: NSNotification.Name("CreateIssueAction"), object: nil)
            }) {
                Text("Create")
                    .font(.body)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .frame(height: LayoutConstants.contentHeaderHeight)
    }
}
