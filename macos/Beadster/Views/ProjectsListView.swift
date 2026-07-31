//
//  ProjectsListView.swift
//  Beadster
//
//  Created by Anton Podviaznikov on 10/19/25.
//

import SwiftUI
import AppKit

struct ProjectsListView: View {
    @ObservedObject var projectStore: ProjectStore
    @Binding var selectedProjectIndex: Int
    @Binding var copiedProjectId: String?
    @Binding var selectedTab: AppTab
    @Binding var contentMode: ContentMode
    @ObservedObject var issueStore: IssueStore

    var body: some View {
        VStack(spacing: 0) {
            if projectStore.projects.isEmpty {
                emptyProjectsView
            } else {
                projectsScrollView
            }
        }
    }

    var emptyProjectsView: some View {
        VStack(spacing: 20) {
            Text("No projects connected")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.bdSecondary)

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
    }

    var projectsScrollView: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(projectStore.projects.enumerated()), id: \.element.id) { index, project in
                    projectRow(index: index, project: project)
                    Divider()
                }
            }
        }
        .onKeyPress(.upArrow) {
            if selectedProjectIndex > 0 {
                selectedProjectIndex -= 1
                projectStore.selectedProject = projectStore.projects[selectedProjectIndex]
            }
            return .handled
        }
        .onKeyPress(.downArrow) {
            if selectedProjectIndex < projectStore.projects.count - 1 {
                selectedProjectIndex += 1
                projectStore.selectedProject = projectStore.projects[selectedProjectIndex]
            }
            return .handled
        }
        .onKeyPress(.return) {
            if selectedProjectIndex < projectStore.projects.count {
                selectedTab = .openIssues
                issueStore.filter = .open
                issueStore.selectedIssueType = nil
                contentMode = .issuesList
            }
            return .handled
        }
        .focusable()
    }

    func projectRow(index: Int, project: ProjectInfo) -> some View {
        ProjectRow(
            project: project,
            showActions: true,
            isSelected: index == selectedProjectIndex,
            copiedProjectId: $copiedProjectId,
            onTap: {
                selectedProjectIndex = index
                projectStore.selectedProject = project
            },
            onRemove: {
                projectStore.removeProject(project)
            }
        )
    }
}
