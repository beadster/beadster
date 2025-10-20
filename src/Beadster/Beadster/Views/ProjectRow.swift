//
//  ProjectRow.swift
//  Beadster
//
//  Created by Anton Podviaznikov on 10/20/25.
//

import SwiftUI
import AppKit

struct ProjectRow: View {
    let project: ProjectInfo
    let showActions: Bool
    let isSelected: Bool
    @Binding var copiedProjectId: String?
    var onTap: (() -> Void)?
    var onRemove: (() -> Void)?

    init(
        project: ProjectInfo,
        showActions: Bool = true,
        isSelected: Bool = false,
        copiedProjectId: Binding<String?> = .constant(nil),
        onTap: (() -> Void)? = nil,
        onRemove: (() -> Void)? = nil
    ) {
        self.project = project
        self.showActions = showActions
        self.isSelected = isSelected
        self._copiedProjectId = copiedProjectId
        self.onTap = onTap
        self.onRemove = onRemove
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder.fill")
                .font(.system(size: 16))
                .foregroundColor(.blue)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(project.name)
                        .font(.system(size: 13))

                    if let sourceId = project.sourceId {
                        Text(sourceId)
                            .font(.system(size: 10).monospaced())
                            .foregroundColor(.secondary)
                    }
                }

                Text(project.path)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                if let lastSync = project.lastSync {
                    Text("Synced \(lastSync.formatted(.relative(presentation: .named)))")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if showActions {
                HStack(spacing: 8) {
                    Button(action: {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: project.path)
                    }) {
                        Image(systemName: "folder")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Open in Finder")

                    Button(action: copyProjectPath) {
                        Image(systemName: copiedProjectId == project.id ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 12))
                            .foregroundColor(copiedProjectId == project.id ? .green : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help(copiedProjectId == project.id ? "Copied!" : "Copy path")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
        .contextMenu {
            if let onRemove = onRemove {
                Button("Remove", role: .destructive) {
                    onRemove()
                }
            }
        }
    }

    private func copyProjectPath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(project.path, forType: .string)
        copiedProjectId = project.id

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            if copiedProjectId == project.id {
                copiedProjectId = nil
            }
        }
    }
}
