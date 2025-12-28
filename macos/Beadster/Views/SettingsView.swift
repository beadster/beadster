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
    @StateObject private var authManager = AuthManager.shared
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
                        .foregroundColor(.bdSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if AppConfig.showAccountUI {
                        AccountSettings(authManager: authManager)
                    }

                    ProjectsSettings(projectStore: projectStore)

                    if AppConfig.showSyncStatus {
                        SyncSettings(syncDaemon: syncDaemon, authManager: authManager)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct ProjectsSettings: View {
    @ObservedObject var projectStore: ProjectStore
    @State private var copiedProjectId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Projects")
                .font(.title3)
                .fontWeight(.semibold)

            if projectStore.projects.isEmpty {
                Text("No projects registered")
                    .foregroundColor(.bdSecondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(projectStore.projects) { project in
                        ProjectRow(
                            project: project,
                            showActions: true,
                            isSelected: false,
                            copiedProjectId: $copiedProjectId,
                            onRemove: {
                                projectStore.removeProject(project)
                            }
                        )
                        Divider()
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
        }
    }
}

struct AccountSettings: View {
    @ObservedObject var authManager: AuthManager

    var body: some View {
        let _ = print("[UI] AccountSettings rendering, isAuthenticated: \(authManager.isAuthenticated)")
        VStack(alignment: .leading, spacing: 16) {
            Text("Account")
                .font(.title3)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 12) {
                if authManager.isAuthenticated, let user = authManager.currentUser {
                    // Signed in state with user info
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Signed in as")
                            Spacer()
                        }
                        HStack {
                            Image(systemName: "person.circle.fill")
                                .font(.title2)
                                .foregroundColor(.blue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.githubName ?? user.githubLogin ?? "Unknown")
                                    .font(.body)
                                if let email = user.githubEmail {
                                    Text(email)
                                        .font(.caption)
                                        .foregroundColor(.bdSecondary)
                                }
                            }
                        }
                    }

                    Button(action: {
                        authManager.signOut()
                    }) {
                        Text("Sign Out")
                            .font(.body)
                    }
                    .buttonStyle(.bordered)
                } else {
                    // Signed out state
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Cloud sync is disabled")
                            .font(.body)
                            .foregroundColor(.bdSecondary)

                        Text("Sign in with GitHub to sync your issues across devices and access them on the web.")
                            .font(.caption)
                            .foregroundColor(.bdSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Button(action: {
                            authManager.signIn()
                        }) {
                            HStack {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text("Sign in with GitHub")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(authManager.isLoading)
                    }
                }

                if let error = authManager.error {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            .padding(.horizontal)
        }
    }
}

struct SyncSettings: View {
    @ObservedObject var syncDaemon: SyncDaemon
    @ObservedObject var authManager: AuthManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sync")
                .font(.title3)
                .fontWeight(.semibold)

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
                            .foregroundColor(.bdSecondary)
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
                    Text("Cloud Sync")
                    Spacer()
                    if authManager.isAuthenticated {
                        Text("Enabled")
                            .foregroundColor(.green)
                    } else {
                        Text("Disabled")
                            .foregroundColor(.orange)
                    }
                }

                if authManager.isAuthenticated {
                    HStack {
                        Text("Auto Sync")
                        Spacer()
                        Text("Every 1 minute")
                            .foregroundColor(.bdSecondary)
                    }
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
                        .foregroundColor(.bdSecondary)
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
