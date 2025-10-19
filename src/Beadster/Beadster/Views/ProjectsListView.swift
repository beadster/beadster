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
                contentMode = .issuesList
            }
            return .handled
        }
        .focusable()
    }

    func projectRow(index: Int, project: ProjectInfo) -> some View {
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
        .background(index == selectedProjectIndex ? Color.blue.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedProjectIndex = index
            projectStore.selectedProject = project
        }
        .contextMenu {
            Button("Remove", role: .destructive) {
                projectStore.removeProject(project)
            }
        }
    }
}
