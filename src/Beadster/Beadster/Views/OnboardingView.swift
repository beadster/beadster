//
//  OnboardingView.swift
//  Beadster
//
//  Created by Anton Podviaznikov on 10/19/25.
//

import SwiftUI
import AppKit

struct OnboardingView: View {
    @ObservedObject var projectStore: ProjectStore

    var body: some View {
        VStack(spacing: 20) {
            Text("Welcome to Beadster")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.black.opacity(0.9))

            Text("Get started by connecting your projects")
                .font(.system(size: 13))
                .foregroundColor(.black.opacity(0.6))
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                Button(action: {
                    projectStore.selectFolderToScan()
                }) {
                    HStack {
                        Image(systemName: "folder.badge.plus")
                        Text("Connect Project Folders")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button(action: {
                    selectClaudeLogs()
                }) {
                    HStack {
                        Image(systemName: "doc.text.magnifyingglass")
                        Text("Connect Claude Logs")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 40)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func selectClaudeLogs() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select your .claude folder for context capture"
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")

        if panel.runModal() == .OK, let url = panel.url {
            print("Selected Claude folder: \(url.path)")
            // TODO: save bookmark for Claude folder
        }
    }
}
