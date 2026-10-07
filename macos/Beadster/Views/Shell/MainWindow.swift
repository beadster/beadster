// The window: sidebar of places and projects, the selected place, an inspector.
// HIG: sidebars.md (top-level collections, counts as badges), toolbars.md (title leading;
// actions, inspector and search trailing), split-views.md.
import BeadsKit
import SwiftUI

struct MainWindow: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 300)
        } detail: {
            PlaceView(model: model)
                .inspector(isPresented: $model.showInspector) {
                    Group {
                        if model.historyTarget != nil { VersionInspector(model: model) }
                        else if model.selection == .agents { LeaseInspector(model: model) }
                        else if model.selection == .memories { MemoryInspector(model: model) }
                        else { BeadInspector(model: model) }
                    }
                    .inspectorColumnWidth(min: 280, ideal: 320)
                }
        }
        .navigationTitle(model.selection.map { title(for: $0) } ?? "Beadster")
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Button("All Projects") {}
                    if !model.entries.isEmpty { Divider() }
                    ForEach(model.entries) { e in Button(e.found.name) {} }
                } label: {
                    Label("Filter", systemImage: "line.3.horizontal.decrease")
                }
                .accessibilityLabel("Filter by project")
                Button {} label: { Label("New Bead", systemImage: "plus") }
                    .accessibilityLabel("New Bead")
                    .disabled(model.entries.isEmpty)
            }
            ToolbarItem(placement: .primaryAction) {
                Button { model.showInspector.toggle() } label: {
                    Label("Inspector", systemImage: "sidebar.trailing")
                }
                .accessibilityLabel(model.showInspector ? "Hide Inspector" : "Show Inspector")
            }
        }
        .searchable(text: $model.search, placement: .toolbar, prompt: "Search beads")
        .sheet(item: $model.pending) { _ in FoundSheet(model: model) }
        .onChange(of: model.selection) { _, place in
            model.historyTarget = nil
            Task { await model.opened(place) }
        }
    }

    private var subtitle: String {
        if model.loading { return "Opening projects…" }
        if model.entries.isEmpty { return "No folders yet" }
        switch model.selection {
        case .needsYou:
            let a = model.needsYou.approvals.count, b = model.needsYou.assigned.count
            return "\(a.formatted()) \(a == 1 ? "approval" : "approvals"), \(b.formatted()) assigned"
        case .agents:
            let quiet = model.working.filter { ($0.bead.lease?.health(at: .now) ?? .active) != .active }.count
            let n = model.working.count
            return "\(n.formatted()) working" + (quiet > 0 ? ", \(quiet.formatted()) not answering" : "")
        case .activity:
            return "The last 7 days"
        case .memories:
            let n = model.memories.count
            return "\(n.formatted()) \(n == 1 ? "memory" : "memories")"
        case .workflows:
            let n = model.workflows.count
            return "\(n.formatted()) \(n == 1 ? "workflow" : "workflows")"
        case .project(let id):
            if model.problem(for: .project(id)) != nil { return "" }
            if case .ready(let n) = model.entry(id)?.state { return "\(n.formatted()) ready" }
            return ""
        case .folder(let key):
            return model.lostFolders.first { $0.key == key }?.path ?? ""
        default:
            let n = model.entries.count
            return "\(model.totalReady.formatted()) ready across \(n.formatted()) \(n == 1 ? "project" : "projects")"
        }
    }

    private func title(for place: Place) -> String {
        if case .project(let id) = place { return model.entry(id)?.found.name ?? "Project" }
        if case .folder(let key) = place {
            return model.lostFolders.first { $0.key == key }.map { URL(fileURLWithPath: $0.path).lastPathComponent } ?? "Folder"
        }
        return place.title
    }
}

struct SidebarView: View {
    @Bindable var model: AppModel

    var body: some View {
        List(selection: $model.selection) {
            Section {
                row(.needsYou, count: model.needsYou.count == 0 ? nil : model.needsYou.count)
                row(.ready, count: model.entries.isEmpty ? nil : model.totalReady)
                row(.agents, count: model.working.isEmpty ? nil : model.working.count)
                row(.blocked)
                row(.activity)
            }
            Section("Library") {
                row(.workflows)
                row(.memories)
            }
            if !model.entries.isEmpty || !model.lostFolders.isEmpty {
                Section("Projects") {
                    ForEach(model.entries) { entry in
                        projectRow(entry)
                    }
                    ForEach(model.lostFolders, id: \.key) { folder in
                        Label(URL(fileURLWithPath: folder.path).lastPathComponent, systemImage: Place.folder(folder.key).symbol)
                            .foregroundStyle(.secondary)
                            .help(Problem.folderLost.title)
                            .tag(Place.folder(folder.key))
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder private func row(_ place: Place, count: Int? = nil) -> some View {
        if let count {
            Label(place.title, systemImage: place.symbol).badge(count).tag(place)
        } else {
            Label(place.title, systemImage: place.symbol).tag(place)
        }
    }

    @ViewBuilder private func projectRow(_ entry: ProjectLibrary.Entry) -> some View {
        if case .ready(let n) = entry.state {
            Label(entry.found.name, systemImage: "folder").badge(n).tag(Place.project(entry.id))
        } else if let problem = Problem.of(entry.state) {
            // the problem's own symbol, so a project that can't open is seen before it is clicked
            Label(entry.found.name, systemImage: problem.symbol)
                .foregroundStyle(.secondary)
                .help(problem.title)
                .tag(Place.project(entry.id))
        } else {
            Label(entry.found.name, systemImage: "folder").tag(Place.project(entry.id))
        }
    }
}

/// The selected place. Each place's real view lands in its own step (U3-U11).
struct PlaceView: View {
    @Bindable var model: AppModel

    var body: some View {
        if let target = model.historyTarget {
            HistoryView(model: model, target: target)
        } else if model.loading && model.entries.isEmpty {
            ProgressView("Opening projects…")
        } else if !model.hasFolders {
            ContentUnavailableView {
                Label("Add a Folder", systemImage: "folder.badge.plus")
            } description: {
                Text("Choose the folder that holds your projects. Beadster finds every project with beads inside it and keeps access, so you choose once.")
            } actions: {
                Button("Choose Folder…") { Task { await model.chooseFolder() } }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        } else if let problem = model.problem(for: model.selection) {
            ProblemView(problem: problem) { action in Task { await model.perform(action, for: model.selection) } }
        } else if let place = model.selection {
            switch place {
            case .ready, .project: ReadyView(model: model)
            case .needsYou: NeedsYouView(model: model)
            case .agents: AgentsView(model: model)
            case .workflows: WorkflowsView(model: model)
            case .activity: ActivityView(model: model)
            case .memories: MemoriesView(model: model)
            default: ContentUnavailableView(place.title, systemImage: place.symbol)
            }
        } else {
            ContentUnavailableView("No Selection", systemImage: "sidebar.left")
        }
    }
}
