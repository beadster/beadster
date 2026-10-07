// The app's state: the granted folders, every project in them (BeadsKit's ProjectLibrary), and
// what the window shows. Views read it; they compute nothing.
import BeadsKit
import Foundation
import SwiftUI

enum Place: Hashable {
    case needsYou, ready, agents, blocked, activity, workflows, memories
    case project(String)

    var title: String {
        switch self {
        case .needsYou: "Needs You"
        case .ready: "Ready"
        case .agents: "Agents"
        case .blocked: "Blocked"
        case .activity: "Activity"
        case .workflows: "Workflows"
        case .memories: "Memories"
        case .project: "Project"
        }
    }

    var symbol: String {
        switch self {
        case .needsYou: "hand.raised"
        case .ready: "checkmark.circle"
        case .agents: "person.2.wave.2"
        case .blocked: "exclamationmark.circle"
        case .activity: "clock.arrow.circlepath"
        case .workflows: "point.3.connected.trianglepath.dotted"
        case .memories: "brain"
        case .project: "folder"
        }
    }
}

@MainActor
@Observable
final class AppModel {
    var selection: Place? = .ready
    var search = ""
    var showInspector = true
    private(set) var entries: [ProjectLibrary.Entry] = []
    private(set) var totalReady = 0
    private(set) var loading = false
    /// How long the last load took, for the rig's report.
    private(set) var lastLoadSeconds: Double?

    let folders = FolderList()
    private let library = ProjectLibrary(engine: FFIEngine())

    var hasFolders: Bool { !folders.folders.isEmpty || !entries.isEmpty }

    /// Opens every project in every granted folder.
    func load() async {
        loading = true
        defer { loading = false }
        for folder in folders.folders {
            guard let access = folders.access(for: folder) else { continue }
            await library.add(folderKey: folder.key, access: access, projects: folders.projects(in: folder))
        }
        await publish()
    }

    func addFolder() async {
        guard let folder = folders.add(), let access = folders.access(for: folder) else { return }
        loading = true
        defer { loading = false }
        await library.add(folderKey: folder.key, access: access, projects: folders.projects(in: folder))
        await publish()
    }

    /// The rig: projects from a folder inside the app's own container, no bookmark needed.
    func load(plainFolder root: URL) async {
        loading = true
        let start = Date()
        await library.add(folderKey: "rig", access: PlainFolder(root), projects: ProjectScanner.scan(root, maxDepth: 1))
        await publish()
        lastLoadSeconds = Date().timeIntervalSince(start)
        loading = false
    }

    private func publish() async {
        entries = await library.all.sorted { $0.found.name.localizedStandardCompare($1.found.name) == .orderedAscending }
        totalReady = await library.totalReady
    }

    func entry(_ id: String) -> ProjectLibrary.Entry? { entries.first { $0.id == id } }
}
