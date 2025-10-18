//
//  SettingsView.swift
//  Beadster
//
//  Created by Anton Podviaznikov on 10/18/25.
//

import SwiftUI

struct SettingsView: View {
    @StateObject private var projectStore = ProjectStore()

    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            ProjectsSettings(projectStore: projectStore)
                .tabItem {
                    Label("Projects", systemImage: "folder")
                }

            SyncSettings()
                .tabItem {
                    Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                }
        }
        .frame(width: 600, height: 500)
        .padding()
    }
}

struct GeneralSettings: View {
    @AppStorage("apiEndpoint") private var apiEndpoint = "https://beadster-dev-app.systemoperator.workers.dev"
    @AppStorage("apiToken") private var apiToken = "dev-token-placeholder"

    var body: some View {
        Form {
            Section("API Configuration") {
                TextField("Endpoint", text: $apiEndpoint)
                    .font(.body.monospaced())

                SecureField("API Token", text: $apiToken)
                    .font(.body.monospaced())

                Text("For production, use Sign in with Apple (coming soon)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("About") {
                HStack {
                    Text("Version:")
                    Spacer()
                    Text("0.1.0 (POC)")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Database:")
                    Spacer()
                    Text("SQLite (.beads/beads.db)")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct ProjectsSettings: View {
    @ObservedObject var projectStore: ProjectStore

    var body: some View {
        VStack(alignment: .leading) {
            Form {
                Section("Registered Projects") {
                    if projectStore.projects.isEmpty {
                        Text("No projects registered")
                            .foregroundColor(.secondary)
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
                            .padding(.vertical, 4)
                            .contextMenu {
                                Button("Remove", role: .destructive) {
                                    projectStore.removeProject(project)
                                }
                            }
                        }
                    }
                }

                Section {
                    Button("Add Projects...") {
                        projectStore.selectFolderToScan()
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct SyncSettings: View {
    @ObservedObject private var syncDaemon = SyncDaemon.shared

    var body: some View {
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
                    Text("Every 5 minutes")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("File Watching:")
                    Spacer()
                    Text("Enabled")
                        .foregroundColor(.green)
                }
            }

            Section {
                Text("Sync automatically triggers on file changes and every 5 minutes")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

#Preview {
    SettingsView()
}
