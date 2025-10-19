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
                VStack(spacing: 24) {
                    ProjectsSettings(projectStore: projectStore)

                    SyncSettings(syncDaemon: syncDaemon)
                }
                .padding(.top, 12)
            }
            .background(Color.white)
        }
    }
}

struct ProjectsSettings: View {
    @ObservedObject var projectStore: ProjectStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Projects")
                .font(.title3)
                .fontWeight(.semibold)
                .padding(.horizontal)

            if projectStore.projects.isEmpty {
                Text("No projects registered")
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            } else {
                ForEach(projectStore.projects) { project in
                    VStack(alignment: .leading, spacing: 8) {
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
                    .padding(.horizontal)
                    .contextMenu {
                        Button("Remove", role: .destructive) {
                            projectStore.removeProject(project)
                        }
                    }
                }
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
        VStack(alignment: .leading, spacing: 16) {
            Text("Sync")
                .font(.title3)
                .fontWeight(.semibold)
                .padding(.horizontal)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Sync Status")
                    Spacer()
                    if syncDaemon.isSyncing {
                        HStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.4)
                                .frame(width: 8, height: 8)
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
                        Text("Last Sync")
                        Spacer()
                        Text(lastSync.formatted(.relative(presentation: .named)))
                            .foregroundColor(.secondary)
                    }
                }

                if let error = syncDaemon.syncError {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Error")
                            Spacer()
                        }
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                HStack {
                    Text("Auto Sync")
                    Spacer()
                    Text("Every 1 minute")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("File Watching")
                    Spacer()
                    Text("Enabled")
                        .foregroundColor(.green)
                }

                HStack {
                    Text("Watching Projects")
                    Spacer()
                    Text("\(syncDaemon.watchedProjectsCount)")
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
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
