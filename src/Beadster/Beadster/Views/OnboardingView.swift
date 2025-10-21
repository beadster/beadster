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
        VStack(alignment: .leading, spacing: 20) {
            Text("welcome to beadster")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.black.opacity(0.9))

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    Text("beadster is native macOS client for")
                        .font(.system(size: 13))
                        .foregroundColor(.black.opacity(0.6))

                    Link("beads", destination: URL(string: "https://github.com/steveyegge/beads")!)
                        .font(.system(size: 13))

//                    Text(".")
//                        .font(.system(size: 13))
//                        .foregroundColor(.black.opacity(0.6))
                }

                Text("you can:")
                    .font(.system(size: 13))
                    .foregroundColor(.black.opacity(0.6))
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 2) {
                    Text("- view beads tasks from different projects")
                        .font(.system(size: 13))
                        .foregroundColor(.black.opacity(0.6))
                    Text("- complete tasks and edit tasks")
                        .font(.system(size: 13))
                        .foregroundColor(.black.opacity(0.6))
                    Text("- create new tasks")
                        .font(.system(size: 13))
                        .foregroundColor(.black.opacity(0.6))
                    Text("- search tasks across all the projects")
                        .font(.system(size: 13))
                        .foregroundColor(.black.opacity(0.6))
                }

                HStack(spacing: 4) {
                    Text("read more")
                        .font(.system(size: 13))
                        .foregroundColor(.black.opacity(0.6))

                    Link("here", destination: URL(string: "https://beadster.ai/")!)
                        .font(.system(size: 13))
                }
                .padding(.top, 4)
            }

            Button(action: {
                projectStore.selectFolderToScan()
            }) {
                HStack {
                    Image(systemName: "folder.badge.plus")
                    Text("Connect Project Folders")
                }
            }
            .buttonStyle(.borderedProminent)

            // Button(action: {
            //     selectClaudeLogs()
            // }) {
            //     HStack {
            //         Image(systemName: "doc.text.magnifyingglass")
            //         Text("Connect Claude Logs")
            //     }
            // }
            // .buttonStyle(.bordered)

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.top, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
