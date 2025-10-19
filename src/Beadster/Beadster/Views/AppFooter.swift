//
//  AppFooter.swift
//  Beadster
//
//  Created by Anton Podviaznikov on 10/19/25.
//

import SwiftUI

struct AppFooter: View {
    @ObservedObject var syncDaemon: SyncDaemon

    var body: some View {
        HStack(spacing: 12) {
            // Left side: Cloud sync status
            HStack(spacing: 6) {
                if syncDaemon.isSyncing {
                    // Syncing badge
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 10, height: 10)
                        Text("Syncing")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.15))
                    .foregroundColor(.blue)
                    .cornerRadius(3)

                    if let issueId = syncDaemon.currentSyncingIssueId {
                        Text("issue \(issueId)")
                            .font(.system(size: 9))
                            .foregroundColor(.black.opacity(0.6))
                    } else {
                        Text("cloud")
                            .font(.system(size: 9))
                            .foregroundColor(.black.opacity(0.6))
                    }
                } else if let error = syncDaemon.syncError {
                    // Error badge
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 8))
                        Text("Error")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.15))
                    .foregroundColor(.orange)
                    .cornerRadius(3)

                    Text(error)
                        .font(.system(size: 9))
                        .foregroundColor(.black.opacity(0.6))
                        .lineLimit(1)
                        .truncationMode(.tail)
                } else if let lastSync = syncDaemon.lastSyncDate {
                    // Synced badge
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 8))
                        Text("Synced")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.15))
                    .foregroundColor(.green)
                    .cornerRadius(3)

                    Text("\(lastSync.formatted(.relative(presentation: .named)))")
                        .font(.system(size: 9))
                        .foregroundColor(.black.opacity(0.6))
                } else {
                    // No sync yet
                    HStack(spacing: 4) {
                        Image(systemName: "cloud")
                            .font(.system(size: 8))
                        Text("Not synced")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.gray.opacity(0.15))
                    .foregroundColor(.gray)
                    .cornerRadius(3)
                }
            }

            Spacer()

            // Right side: Local sync status
            HStack(spacing: 6) {
                if syncDaemon.watchedProjectsCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                            .font(.system(size: 8))
                        Text("Watching")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.15))
                    .foregroundColor(.blue)
                    .cornerRadius(3)

                    Text("\(syncDaemon.watchedProjectsCount) project\(syncDaemon.watchedProjectsCount == 1 ? "" : "s")")
                        .font(.system(size: 9))
                        .foregroundColor(.black.opacity(0.6))

                    if let lastChange = syncDaemon.lastLocalChangeDate {
                        Text("• changed \(lastChange.formatted(.relative(presentation: .named)))")
                            .font(.system(size: 9))
                            .foregroundColor(.black.opacity(0.5))
                    }
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                            .font(.system(size: 8))
                        Text("No projects")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.gray.opacity(0.15))
                    .foregroundColor(.gray)
                    .cornerRadius(3)
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: LayoutConstants.footerHeight)
        .background(Color.yellow.opacity(0.3)) // DEBUG
        .border(Color.yellow, width: 2) // DEBUG
    }
}
