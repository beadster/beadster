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
                // Settings has its own header, hide this one
                EmptyView()
                    .frame(height: 0)
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
        .background(Color.green.opacity(0.3)) // DEBUG
        .border(Color.green, width: 2) // DEBUG
    }
}
