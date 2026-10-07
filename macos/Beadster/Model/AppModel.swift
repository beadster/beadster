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
            await library.add(folderKey: folder.key, access: access, projects: folder.included(folders.projects(in: folder)))
        }
        await publish()
    }

    /// A folder the person just chose, waiting for them to pick its projects in the sheet.
    struct PendingFolder: Identifiable {
        var id: String { folder.key }
        var folder: GrantedFolder
        let found: [FoundProject]
        var states: [String: ProjectLibrary.State]
        var chosen: Set<String>
    }

    var pending: PendingFolder?

    /// Choose Folder…: the panel, then the projects found in it for the sheet.
    func chooseFolder() async {
        guard let folder = folders.pick(), let access = folders.access(for: folder) else { return }
        await present(folder, access: access, found: folders.projects(in: folder))
    }

    func present(_ folder: GrantedFolder, access: any FolderAccess, found: [FoundProject]) async {
        loading = true
        defer { loading = false }
        let states = await library.preview(access: access, projects: found)
        let openable = found.filter { $0.kind == .embedded }.map(\.relativePath)
        pending = PendingFolder(folder: folder, found: found, states: states, chosen: Set(openable))
    }

    /// Add N Projects: keep the folder with what was unticked, open the rest.
    func confirmPending() async {
        guard var p = pending, let access = folders.access(for: p.folder) else { pending = nil; return }
        p.folder.excluded = p.found.map(\.relativePath).filter { !p.chosen.contains($0) }
        pending = nil
        folders.keep(p.folder)
        loading = true
        defer { loading = false }
        await library.add(folderKey: p.folder.key, access: access, projects: p.folder.included(p.found))
        await publish()
    }

    func cancelPending() {
        if let p = pending { folders.discard(p.folder) }
        pending = nil
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
