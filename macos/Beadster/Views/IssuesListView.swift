//
//  IssuesListView.swift
//  Beadster
//
//  Created by Anton Podviaznikov on 10/19/25.
//

import SwiftUI

struct IssuesListView: View {
    @ObservedObject var issueStore: IssueStore
    @EnvironmentObject var projectStore: ProjectStore
    @Binding var selectedIssueIndex: Int
    @Binding var contentMode: ContentMode
    let viewMode: ViewMode
    @FocusState private var isFocused: Bool

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if issueStore.isLoading {
                    ProgressView()
                        .padding()
                } else if issueStore.filteredIssues().isEmpty {
                    emptyIssuesView
                } else {
                    issuesList
                }
            }
            .animation(.easeInOut(duration: 0.2), value: issueStore.issues)
        }
        .focusable()
        .focused($isFocused)
        .onAppear {
            isFocused = true
        }
        .onKeyPress(.upArrow) {
            if selectedIssueIndex > 0 {
                selectedIssueIndex -= 1
            }
            return .handled
        }
        .onKeyPress(.downArrow) {
            let issues = issueStore.filteredIssues()
            if selectedIssueIndex < issues.count - 1 {
                selectedIssueIndex += 1
            }
            return .handled
        }
        .onKeyPress(.return) {
            let issues = issueStore.filteredIssues()
            if selectedIssueIndex < issues.count {
                contentMode = .issueDetail(issues[selectedIssueIndex])
            }
            return .handled
        }
    }

    var emptyIssuesView: some View {
        VStack(alignment: .leading, spacing: 12) {
            if projectStore.projects.isEmpty {
                Text("No issues, please add project")
                    .font(.body)
                    .foregroundColor(.bdSecondary)

                Button(action: {
                    projectStore.selectFolderToScan()
                }) {
                    HStack {
                        Image(systemName: "folder.badge.plus")
                        Text("Add Projects")
                    }
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text("No issues")
                    .font(.body)
                    .foregroundColor(.bdSecondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    var issuesList: some View {
        if viewMode == .tree {
            // Tree view: show issues in dependency hierarchy
            let treeNodes = buildIssueTree(
                issues: issueStore.filteredIssues(),
                dependencies: issueStore.dependencies
            )
            ForEach(Array(treeNodes.enumerated()), id: \.element.id) { index, node in
                renderTreeNode(node)
            }
        } else {
            // List view: show flat list
            let issues = issueStore.filteredIssues()
            ForEach(Array(issues.enumerated()), id: \.element.id) { index, issue in
                IssueRowCompact(issue: issue, issueStore: issueStore, viewMode: viewMode, depth: 0)
                    .environmentObject(projectStore)
                    .contentShape(Rectangle())
                    .background(index == selectedIssueIndex ? Color.blue.opacity(0.1) : Color.clear)
                    .onTapGesture {
                        selectedIssueIndex = index
                        contentMode = .issueDetail(issue)
                    }
                    .transition(.opacity)

                Divider()
            }
        }
    }

    func renderTreeNode(_ node: IssueTreeNode) -> AnyView {
        AnyView(
            Group {
                IssueRowCompact(issue: node.issue, issueStore: issueStore, viewMode: viewMode, depth: node.depth)
                    .environmentObject(projectStore)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        contentMode = .issueDetail(node.issue)
                    }

                Divider()

                ForEach(node.children) { child in
                    renderTreeNode(child)
                }
            }
        )
    }

    func buildIssueTree(issues: [Issue], dependencies: [IssueDependency]) -> [IssueTreeNode] {
        // Build lookup maps
        let issueMap = Dictionary(uniqueKeysWithValues: issues.map { ($0.id, $0) })

        // Build children map: issueId depends_on dependsOnId means:
        // issueId is BLOCKED BY dependsOnId
        // So dependsOnId is the parent, issueId is the child
        var childrenMap: [String: [String]] = [:]
        for dep in dependencies {
            // dep.issueId depends on dep.dependsOnId
            // So dep.dependsOnId has dep.issueId as a child (blocked issue)
            childrenMap[dep.dependsOnId, default: []].append(dep.issueId)
        }

        // Find root issues (issues that don't depend on anything in the filtered set)
        let dependentIssueIds = Set(dependencies.map { $0.issueId })
        let rootIssues = issues.filter { !dependentIssueIds.contains($0.id) }

        // Build tree recursively
        func buildNode(issueId: String, depth: Int) -> IssueTreeNode? {
            guard let issue = issueMap[issueId] else { return nil }

            let childIds = childrenMap[issueId] ?? []
            let children = childIds.compactMap { buildNode(issueId: $0, depth: depth + 1) }

            return IssueTreeNode(issue: issue, children: children, depth: depth)
        }

        return rootIssues.compactMap { buildNode(issueId: $0.id, depth: 0) }
    }
}
