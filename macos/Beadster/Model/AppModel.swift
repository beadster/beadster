// The app's state: the granted folders, every project in them (BeadsKit's ProjectLibrary), and
// what the window shows. Views read it; they compute nothing.
import AppKit
import BeadsKit
import FSEventsWatcher
import Foundation
import SwiftUI

enum Place: Hashable {
    case needsYou, ready, agents, blocked, activity, workflows, memories
    case project(String)
    /// A granted folder beadster can no longer reach (its key).
    case folder(String)

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
        case .folder: "Folder"
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
        case .folder: "folder.badge.questionmark"
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
        checkFolders()
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
        let saved = UserDefaults.standard.string(forKey: "actorName")?.trimmingCharacters(in: .whitespaces) ?? ""
        return saved.isEmpty ? NSUserName() : saved
    }

    /// Settings › Folders › Remove: closes its projects and forgets its bookmark.
    func removeFolder(_ folder: GrantedFolder) async {
        await library.remove(folderKey: folder.key)
        folders.remove(folder)
        checkFolders()
        await publishAll()
    }

    // MARK: Problems

    /// Granted folders that are gone or whose access ended: listed in the sidebar to choose again.
    private(set) var lostFolders: [GrantedFolder] = []
    /// Open projects with no bead at all, told apart from "nothing ready".
    private(set) var emptyProjects: Set<String> = []

    func checkFolders() {
        lostFolders = folders.folders.filter { folders.access(for: $0) == nil || folders.health(of: $0) == .missing }
    }

    /// What the selected place shows instead of beads, if anything.
    func problem(for place: Place?) -> Problem? {
        switch place {
        case .folder: return .folderLost
        case .project(let id):
            if let state = entry(id)?.state, let problem = Problem.of(state) { return problem }
            return emptyProjects.contains(id) ? .noBeadsYet : nil
        case .ready:
            let open = entries.filter { if case .ready = $0.state { true } else { false } }
            return !open.isEmpty && open.allSatisfy { emptyProjects.contains($0.id) } ? .noBeadsYet : nil
        default: return nil
        }
    }

    func perform(_ action: Problem.Action, for place: Place?) async {
        switch (action, place) {
        case (.upgradeProject, .project(let id)?):
            await library.upgrade(id)
            await publishAll()
        case (.tryAgain, .project(let id)?):
            await library.refresh(id)
            await publishAll()
        case (.updateApp, _):
            if let url = URL(string: "macappstore://apps.apple.com/app/id6754286462") { NSWorkspace.shared.open(url) }
        case (.openGuide, _):
            NSWorkspace.shared.open(BeadsVersion.upgradeGuide)
        case (.chooseFolderAgain, .folder(let key)?):
            // the old bookmark reaches nothing: the new folder replaces it
            guard let new = folders.pick(), let access = folders.access(for: new) else { return }
            if let old = folders.folders.first(where: { $0.key == key }) { await removeFolder(old) }
            checkFolders()
            selection = .ready
            await present(new, access: access, found: folders.projects(in: new))
        default: break
        }
    }

    /// How many projects beadster opened from a folder.
    func projectCount(in folder: GrantedFolder) -> Int {
        entries.filter { $0.folderKey == folder.key }.count
    }

    func loadReady() async {
        var empty: Set<String> = []
        for e in entries {
            if case .ready(0) = e.state, await !library.hasBeads(e.id) { empty.insert(e.id) }
        }
        emptyProjects = empty
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
            lastError = error.report
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
    func load(plainFolder root: URL, key: String = "rig") async {
        loading = true
        let start = Date()
        loadStart = start
        await library.add(folderKey: key, access: PlainFolder(root), projects: ProjectScanner.scan(root, maxDepth: 1))
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
        if selection == .memories { await loadMemories() }
        if let loadStart { lastLoadSeconds = Date().timeIntervalSince(loadStart) }
        backgroundLoading = false
        await notifier.update(needsYou: needsYou, working: working, closed: [])
        await watch()
    }

    /// The screenshot rig's scene is still setting itself up (ShotMode waits for it).
    var sceneBusy = false

    /// Needs You and Agents counts still being read after the window showed.
    private(set) var backgroundLoading = false

    /// A place was opened: read what only it needs.
    func opened(_ place: Place?) async {
        if place == .workflows && workflows.isEmpty { await loadWorkflows() }
        if place == .activity && !activityLoaded { await loadActivity() }
        if place == .memories && !memoriesLoaded { await loadMemories() }
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
            lastError = error.report
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

    // MARK: Memories

    struct MemoryRow: Identifiable, Hashable {
        var id: String { "\(projectID)|\(memory.key)" }
        let projectID: String
        let project: String
        let memory: Memory
    }

    private(set) var memories: [MemoryRow] = []
    var selectedMemory: MemoryRow.ID?
    private var memoriesLoaded = false

    func loadMemories() async {
        memories = await library.memoriesEverywhere().map { MemoryRow(projectID: $0.projectID, project: $0.project, memory: $0.memory) }
        memoriesLoaded = true
    }

    /// Saves new text under the same key (bd remember --key), or forgets the memory.
    func saveMemory(_ row: MemoryRow, text: String) async {
        await memoryWrite(row) { ws, actor throws(BeadsError) in try await ws.remember(text, key: row.memory.key, as: actor) }
    }

    func forgetMemory(_ row: MemoryRow) async {
        await memoryWrite(row) { ws, actor throws(BeadsError) in try await ws.forget(row.memory.key, as: actor) }
        selectedMemory = nil
    }

    private func memoryWrite(_ row: MemoryRow, _ change: (Workspace, String) async throws(BeadsError) -> Void) async {
        guard let ws = await library.workspace(row.projectID) else { return }
        do {
            try await change(ws, actor)
            lastError = nil
        } catch {
            lastError = error.report
        }
        await loadMemories()
    }

    // MARK: A bead's history

    struct HistoryTarget: Equatable {
        let projectID: String
        let project: String
        let bead: Bead
    }

    /// The bead whose Dolt history fills the detail, if one is open.
    var historyTarget: HistoryTarget?
    private(set) var historyEntries: [HistoryEntry] = []
    private(set) var historyChanges: [FieldChange] = []
    var selectedChange: FieldChange.ID?

    func showHistory(of bead: Bead, in projectID: String) async {
        historyTarget = HistoryTarget(projectID: projectID, project: entry(projectID)?.found.name ?? "", bead: bead)
        guard let ws = await library.workspace(projectID) else { return }
        historyEntries = (try? await ws.history(bead.id)) ?? []
        let events = (try? await ws.events(after: nil, about: bead.id))?.events ?? []
        historyChanges = BeadHistory.changes(historyEntries, events: events)
        selectedChange = historyChanges.first?.id
    }

    /// The bead as it was just before the selected change.
    var versionBeforeSelected: (bead: Bead, at: Date)? {
        guard let id = selectedChange, let change = historyChanges.first(where: { $0.id == id }) else { return nil }
        let earlier = historyEntries.filter { $0.date < change.at && $0.bead != nil }.max { $0.date < $1.date }
        guard let e = earlier, let b = e.bead else { return nil }
        return (b, e.date)
    }

    func restoreSelected() async {
        guard let target = historyTarget, let version = versionBeforeSelected,
              let ws = await library.workspace(target.projectID) else { return }
        do {
            try await ws.restore(target.bead.id, to: version.bead, as: actor)
            lastError = nil
        } catch {
            lastError = error.report
        }
        await showHistory(of: target.bead, in: target.projectID)
        await library.refresh(target.projectID)
        await publish()
        await loadReady()
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
        let name = entry(projectID)?.found.name ?? ""
        let closed = batch.filter { $0.kind == "closed" }.map { event in
            ActivityItem(projectID: projectID, project: name, event: event,
                         title: (readyRows.map(\.bead) + working.map(\.bead)).first { $0.id == event.beadID }?.title)
        }
        await notifier.update(needsYou: needsYou, working: working, closed: closed)
    }

    // MARK: Notifications

    @ObservationIgnored private lazy var notifier: Notifier = {
        let n = Notifier()
        n.onAction = { [weak self] notice, action in await self?.answer(notice, action) }
        return n
    }()

    /// A banner was answered: Approve or Reject decide the gate right there; a click opens
    /// the place it is about.
    private func answer(_ notice: (kind: String, projectID: String, beadID: String), _ action: String) async {
        if notice.kind == Notice.Kind.gate.rawValue,
           let gate = needsYou.approvals.first(where: { $0.projectID == notice.projectID && $0.gate.id == notice.beadID })?.gate,
           action == Notifier.approve || action == Notifier.reject {
            await decide(gate: gate, in: notice.projectID, approve: action == Notifier.approve)
            return
        }
        switch notice.kind {
        case Notice.Kind.gate.rawValue, Notice.Kind.assigned.rawValue: selection = .needsYou
        case Notice.Kind.quiet.rawValue:
            selection = .agents
            await inspectWork("\(notice.projectID)|\(notice.beadID)")
        default: selection = .activity
        }
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
            lastError = error.report
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
