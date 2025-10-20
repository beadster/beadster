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

                        TextField("Issue title", text: $title)
                            .textFieldStyle(.plain)
                            .font(.body)
                    }

                    // Description
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Description (optional)")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        TextEditor(text: $description)
                            .font(.body)
                            .frame(minHeight: 100)
                            .border(Color.gray.opacity(0.3))
                    }

                    // Priority
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Priority")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Picker("Priority", selection: $priority) {
                            Text("P0 (Critical)").tag(0)
                            Text("P1 (High)").tag(1)
                            Text("P2 (Medium)").tag(2)
                            Text("P3 (Low)").tag(3)
                            Text("P4 (Backlog)").tag(4)
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
