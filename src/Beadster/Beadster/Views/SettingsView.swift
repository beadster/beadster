//
//  SettingsView.swift
//  Beadster
//
//  Created by Anton Podviaznikov on 10/18/25.
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var projectStore: ProjectStore
    @ObservedObject var syncDaemon: SyncDaemon
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header with close button
            HStack {
                Text("Settings")
                    .font(.headline)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    ProjectsSettings(projectStore: projectStore)

                    Divider()
                        .padding(.vertical, 12)

                    SyncSettings(syncDaemon: syncDaemon)
                }
            }
            .background(Color.white)
        }
    }
}

struct ProjectsSettings: View {
    @ObservedObject var projectStore: ProjectStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Projects")
                .font(.title3)
                .fontWeight(.semibold)
                .padding(.horizontal)

            VStack(alignment: .leading, spacing: 8) {
                Text("Registered Projects")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .padding(.horizontal)
                if projectStore.projects.isEmpty {
                    Text("No projects registered")
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                } else {
                    ForEach(projectStore.projects) { project in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(project.name)
                                    .font(.body)
                                Spacer()
                                if let sourceId = project.sourceId {
                                    Text(sourceId)
                                        .font(.caption.monospaced())
                                        .foregroundColor(.secondary)
                                }
                            }

                            Text(project.path)
                                .font(.caption)
                                .foregroundColor(.secondary)

                            if let lastSync = project.lastSync {
                                Text("Last sync: \(lastSync.formatted(.relative(presentation: .named)))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .background(Color.white)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                        .contextMenu {
                            Button("Remove", role: .destructive) {
                                projectStore.removeProject(project)
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                Button(action: {
                    projectStore.selectFolderToScan()
                }) {
                    Text("Add Projects...")
                        .font(.body)
                }
                .buttonStyle(.bordered)
                .padding(.horizontal)
            }
        }
    }


struct SyncSettings: View {
    @ObservedObject var syncDaemon: SyncDaemon

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sync")
                .font(.title3)
                .fontWeight(.semibold)
                .padding(.horizontal)

            Form {
            Section("Status") {
                HStack {
                    Text("Sync Status:")
                    Spacer()
                    if syncDaemon.isSyncing {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Syncing...")
                        }
                        .foregroundColor(.blue)
                    } else {
                        Text("Idle")
                            .foregroundColor(.green)
                    }
                }

                if let lastSync = syncDaemon.lastSyncDate {
                    HStack {
                        Text("Last Sync:")
                        Spacer()
                        Text(lastSync.formatted(.relative(presentation: .named)))
                            .foregroundColor(.secondary)
                    }
                }

                if let error = syncDaemon.syncError {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Error:")
                            .foregroundColor(.red)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }

            Section("Configuration") {
                HStack {
                    Text("Auto Sync:")
                    Spacer()
                    Text("Every 1 minute")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("File Watching:")
                    Spacer()
                    Text("Enabled")
                        .foregroundColor(.green)
                }

                HStack {
                    Text("Watching Projects:")
                    Spacer()
                    Text("\(syncDaemon.watchedProjectsCount)")
                        .foregroundColor(.secondary)
                }
            }

            Section {
                Text("Sync automatically triggers on file changes and every 1 minute")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            }
            .formStyle(.grouped)
        }
    }
}

#Preview {
    SettingsView(
        projectStore: ProjectStore(),
        syncDaemon: SyncDaemon.shared,
        onClose: {}
    )
}
