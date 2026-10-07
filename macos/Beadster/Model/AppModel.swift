// The app's state: the granted folders, every project in them (BeadsKit's ProjectLibrary), and
// what the window shows. Views read it; they compute nothing.
import BeadsKit
import FSEventsWatcher
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
    /// How long the last load took, for the rig's report: until Ready showed, and until every
    /// count was in.
    private(set) var lastLoadSeconds: Double?
    private(set) var firstPaintSeconds: Double?
    private var loadStart: Date?

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
        await publishAll()
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

    // MARK: Ready and the inspector

    /// One ready bead and the project it lives in.
    struct Row: Identifiable, Hashable {
        var id: String { "\(projectID)|\(bead.id)" }
        let projectID: String
        let project: String
        let bead: Bead
    }

    private(set) var readyRows: [Row] = []
    var selectedRow: Row.ID?
    private(set) var inspected: Bead?
    private(set) var inspectedHistory: [AuditEvent] = []
    private(set) var lastError: String?

    /// The name every write carries (Settings › You); the account name until set.
    var actor: String {
        UserDefaults.standard.string(forKey: "actorName") ?? NSUserName()
    }

    func loadReady() async {
        readyRows = await library.readyEverywhere().map {
            Row(projectID: $0.project.id, project: $0.project.found.name, bead: $0.bead)
        }
    }

    /// Ready rows for the current place: all of them, or one project's.
    var visibleReady: [Row] {
        var rows = readyRows
        if case .project(let id) = selection { rows = rows.filter { $0.projectID == id } }
        let q = search.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            rows = rows.filter { $0.bead.title.localizedCaseInsensitiveContains(q) || $0.bead.id.localizedCaseInsensitiveContains(q) }
        }
        return rows
    }

    func inspect(_ id: Row.ID?) async {
        selectedRow = id
        guard let id, let row = readyRows.first(where: { $0.id == id }),
              let ws = await library.workspace(row.projectID) else {
            inspected = nil
            inspectedHistory = []
            return
        }
        inspected = try? await ws.show(row.bead.id)
        inspectedHistory = ((try? await ws.events(after: nil, about: row.bead.id))?.events ?? []).reversed()
    }

    /// One write on the inspected bead, then everything it touches is read again.
    func write(_ change: @escaping (Workspace, String, String) async throws(BeadsError) -> Void) async {
        guard let id = selectedRow, let row = readyRows.first(where: { $0.id == id }),
              let ws = await library.workspace(row.projectID) else { return }
        do {
            try await change(ws, row.bead.id, actor)
            lastError = nil
        } catch {
            lastError = "\(error)"
        }
        await library.refresh(row.projectID)
        await publish()
        await loadReady()
        await inspect(readyRows.contains { $0.id == id } ? id : nil)
    }

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
        await publishAll()
    }

    func cancelPending() {
        if let p = pending { folders.discard(p.folder) }
        pending = nil
    }

    /// The rig: projects from a folder inside the app's own container, no bookmark needed.
    func load(plainFolder root: URL) async {
        loading = true
        let start = Date()
        loadStart = start
        await library.add(folderKey: "rig", access: PlainFolder(root), projects: ProjectScanner.scan(root, maxDepth: 1))
        await publishAll()
        loading = false
    }

    /// The window shows as soon as projects and Ready are in; the other places' counts fill in
    /// after, and Workflows reads only when it is opened.
    func publishAll() async {
        await publish()
        await loadReady()
        loading = false
        if let loadStart { firstPaintSeconds = Date().timeIntervalSince(loadStart) }
        backgroundLoading = true
        await loadNeedsYou()
        await loadWorking()
        if selection == .workflows { await loadWorkflows() }
        if selection == .activity { await loadActivity() }
        if let loadStart { lastLoadSeconds = Date().timeIntervalSince(loadStart) }
        backgroundLoading = false
        await watch()
    }

    /// Needs You and Agents counts still being read after the window showed.
    private(set) var backgroundLoading = false

    /// A place was opened: read what only it needs.
    func opened(_ place: Place?) async {
        if place == .workflows && workflows.isEmpty { await loadWorkflows() }
        if place == .activity && !activityLoaded { await loadActivity() }
    }

    // MARK: Agents

    struct WorkRow: Identifiable, Hashable {
        var id: String { "\(projectID)|\(bead.id)" }
        let projectID: String
        let project: String
        let bead: Bead
    }

    private(set) var working: [WorkRow] = []
    var selectedWork: WorkRow.ID?
    private(set) var workHistory: [AuditEvent] = []

    func loadWorking() async {
        working = await library.workingEverywhere().map { WorkRow(projectID: $0.projectID, project: $0.project, bead: $0.bead) }
    }

    func inspectWork(_ id: WorkRow.ID?) async {
        selectedWork = id
        guard let id, let row = working.first(where: { $0.id == id }), let ws = await library.workspace(row.projectID) else {
            workHistory = []
            return
        }
        workHistory = ((try? await ws.events(after: nil, about: row.bead.id))?.events ?? []).reversed()
    }

    /// Release Now: hands the bead back to Ready. Naming the holder authorizes it; if the
    /// agent changed hands since, beads refuses and nothing is written.
    func release(_ row: WorkRow) async {
        guard let ws = await library.workspace(row.projectID) else { return }
        do {
            try await ws.release(row.bead.id, heldBy: row.bead.assignee, as: actor)
            lastError = nil
        } catch {
            lastError = "\(error)"
        }
        await library.refresh(row.projectID)
        await publishAll()
        await inspectWork(nil)
    }

    // MARK: Workflows

    struct FlowRow: Identifiable {
        var id: String { "\(projectID)|\(workflow.id)" }
        let projectID: String
        let project: String
        let workflow: Workflow
    }

    private(set) var workflows: [FlowRow] = []
    /// The workflow drawn as a map, if one is open.
    var mapped: FlowRow.ID?

    func loadWorkflows() async {
        workflows = await library.workflowsEverywhere().map { FlowRow(projectID: $0.projectID, project: $0.project, workflow: $0.workflow) }
    }

    // MARK: Activity and live updates

    private(set) var activity: [ActivityItem] = []
    private var activityLoaded = false
    private var watchers: [String: FSEventsWatcher] = [:]
    private var feeds: [String: LiveFeed] = [:]

    /// The last 7 days of changes across every project, newest first.
    func loadActivity() async {
        activity = await library.activity(since: Date().addingTimeInterval(-7 * 86_400))
        activityLoaded = true
    }

    /// Watches every open project's .beads: a bd write by an agent (or by this app) re-counts
    /// the project and puts its new changes on top of Activity. FSEvents says "something
    /// changed"; the project's LiveFeed reads exactly what is new from beads' audit log.
    func watch() async {
        for entry in entries where watchers[entry.id] == nil {
            guard case .ready = entry.state, let ws = entry.workspace else { continue }
            let feed = LiveFeed(workspace: ws, after: nil)
            try? await feed.startAtNow()
            feeds[entry.id] = feed
            let id = entry.id
            let watcher = FSEventsWatcher(paths: [ws.project.beadsDir.path], latency: 0.3) { events in
                guard events.contains(where: { !$0.isHistoryDone }) else { return }
                Task { await feed.changed() }
            }
            watcher.start()
            watchers[id] = watcher
            Task { [weak self] in
                for await batch in feed.updates { await self?.changed(id, batch) }
            }
        }
    }

    private func changed(_ projectID: String, _ batch: [AuditEvent]) async {
        await library.refresh(projectID)
        await publish()
        await loadReady()
        if activityLoaded {
            let name = entry(projectID)?.found.name ?? ""
            // titles from beads already on screen; anything else shows its id until the next read
            let known = Dictionary((readyRows.map(\.bead) + working.map(\.bead)).map { ($0.id, $0.title) }, uniquingKeysWith: { a, _ in a })
            let fresh = batch.map { ActivityItem(projectID: projectID, project: name, event: $0, title: known[$0.beadID]) }
            activity = ActivityItem.grouped(fresh.reversed() + activity)
        }
        await loadNeedsYou()
        await loadWorking()
        if selection == .workflows { await loadWorkflows() }
    }

    // MARK: Needs You

    private(set) var needsYou = ProjectLibrary.NeedsYou()

    func loadNeedsYou() async {
        needsYou = await library.needsYou(actor)
    }

    /// Approve or reject a gate: approve releases the work it holds, reject leaves it shut with
    /// the reason as a comment (beads has no reject).
    func decide(gate: Gate, in projectID: String, approve: Bool) async {
        guard let ws = await library.workspace(projectID) else { return }
        do {
            if approve { try await ws.approve(gate: gate.id, as: actor) }
            else { try await ws.reject(gate: gate.id, as: actor) }
            lastError = nil
        } catch {
            lastError = "\(error)"
        }
        await library.refresh(projectID)
        await publishAll()
    }

    private func publish() async {
        entries = await library.all.sorted { $0.found.name.localizedStandardCompare($1.found.name) == .orderedAscending }
        totalReady = await library.totalReady
    }

    func entry(_ id: String) -> ProjectLibrary.Entry? { entries.first { $0.id == id } }
}
