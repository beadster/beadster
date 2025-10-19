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
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(spacing: 24) {
                    AccountSettings(authManager: authManager)

                    ProjectsSettings(projectStore: projectStore)

                    SyncSettings(syncDaemon: syncDaemon, authManager: authManager)
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

                        if let gitRepoUrl = project.gitRepoUrl {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.triangle.branch")
                                    .font(.caption2)
                                Text(extractRepoName(from: gitRepoUrl))
                                    .font(.caption.monospaced())
                                if let branch = project.gitCurrentBranch {
                                    Text("(\(branch))")
                                        .font(.caption2)
                                }
                            }
                            .foregroundColor(.blue)
                        }

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

    private func extractRepoName(from url: String) -> String {
        // Extract repo name from git URL
        // https://github.com/user/repo.git -> user/repo
        // git@github.com:user/repo.git -> user/repo
        if let match = url.range(of: #"([^/:]+/[^/:]+?)(\.git)?$"#, options: .regularExpression) {
            var name = String(url[match])
            if name.hasSuffix(".git") {
                name = String(name.dropLast(4))
            }
            return name
        }
        return url
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
                .padding(.horizontal)

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
                                        .foregroundColor(.secondary)
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
                            .foregroundColor(.secondary)

                        Text("Sign in with GitHub to sync your issues across devices and access them on the web.")
                            .font(.caption)
                            .foregroundColor(.secondary)
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
                            .foregroundColor(.secondary)
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
