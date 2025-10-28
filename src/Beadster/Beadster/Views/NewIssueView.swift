//
//  NewIssueView.swift
//  Beadster
//
//  Created by Anton Podviaznikov on 10/20/25.
//

import SwiftUI

struct NewIssueView: View {
    @ObservedObject var issueStore: IssueStore
    @ObservedObject var projectStore: ProjectStore
    @Binding var contentMode: ContentMode

    @State private var title: String = ""
    @State private var description: String = ""
    @State private var priority: Int = 1 // P1 by default
    @State private var status: IssueStatus = .open
    @State private var issueType: IssueType = .task
    @State private var selectedProjectId: String?
    @State private var isCreating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Form
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Project selector
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Project")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Picker("Project", selection: $selectedProjectId) {
                            Text("Select project...").tag(nil as String?)
                            ForEach(projectStore.projects, id: \.name) { project in
                                Text(project.name).tag(project.name as String?)
                            }
                        }
                        .labelsHidden()
                    }

                    // Title
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Title")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        TextField("Enter issue title", text: $title)
                            .textFieldStyle(.roundedBorder)
                            .font(.body)
                    }

                    // Description
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Description (optional)")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        ZStack(alignment: .topLeading) {
                            if description.isEmpty {
                                Text("Enter issue description")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 8)
                            }

                            TextEditor(text: $description)
                                .font(.body)
                                .frame(minHeight: 100)
                                .padding(4)
                                .scrollContentBackground(.hidden)
                                .background(Color(nsColor: .textBackgroundColor))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                                )
                        }
                    }

                    // Priority
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Priority")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Picker("Priority", selection: $priority) {
                            ForEach(IssuePriority.allCases, id: \.self) { priorityCase in
                                Text(priorityCase.description).tag(priorityCase.rawValue)
                            }
                        }
                        .labelsHidden()
                    }

                    // Status
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Status")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Picker("Status", selection: $status) {
                            ForEach(IssueStatus.allCases, id: \.self) { status in
                                Text(status.displayName).tag(status)
                            }
                        }
                        .labelsHidden()
                    }

                    // Type
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Type")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Picker("Type", selection: $issueType) {
                            ForEach(IssueType.allCases, id: \.self) { type in
                                Text(type.displayName).tag(type)
                            }
                        }
                        .labelsHidden()
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 12)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CreateIssueAction"))) { _ in
            if !title.isEmpty && selectedProjectId != nil && !isCreating {
                createIssue()
            }
        }
        .onAppear {
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == 53 { // ESC key
                    contentMode = .issuesList
                    return nil // Consume the event
                }
                return event
            }
        }
    }

    private func createIssue() {
        guard !title.isEmpty, let projectName = selectedProjectId else { return }
        guard let project = projectStore.projects.first(where: { $0.name == projectName }) else { return }

        isCreating = true

        Task {
            do {
                // Create issue via IssueStore
                try await issueStore.createIssue(
                    projectPath: project.path,
                    title: title,
                    description: description.isEmpty ? nil : description,
                    priority: priority,
                    status: status.rawValue,
                    issueType: issueType.rawValue,
                    labels: []
                )

                // Reload issues
                await issueStore.loadIssuesFromAllProjects(projects: projectStore.projects)

                // Go back to list
                await MainActor.run {
                    contentMode = .issuesList
                }
            } catch {
                print("Failed to create issue: \(error)")
                isCreating = false
            }
        }
    }
}
