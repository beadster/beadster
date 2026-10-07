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
        case .workflows:
            let n = model.workflows.count
            return "\(n.formatted()) \(n == 1 ? "workflow" : "workflows")"
        case .project(let id):
            if case .ready(let n) = model.entry(id)?.state { return "\(n.formatted()) ready" }
            return ""
        default:
            let n = model.entries.count
            return "\(model.totalReady.formatted()) ready across \(n.formatted()) \(n == 1 ? "project" : "projects")"
        }
    }

    private func title(for place: Place) -> String {
        if case .project(let id) = place { return model.entry(id)?.found.name ?? "Project" }
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
            if !model.entries.isEmpty {
                Section("Projects") {
                    ForEach(model.entries) { entry in
                        projectRow(entry)
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
        let label = Label(entry.found.name, systemImage: "folder")
        if case .ready(let n) = entry.state {
            label.badge(n).tag(Place.project(entry.id))
        } else {
            // states other than ready get their own drawing in U15; until then, the reason on hover
            label.help(reason(entry.state)).tag(Place.project(entry.id))
        }
    }

    private func reason(_ state: ProjectLibrary.State) -> String {
        switch state {
        case .opening: "Opening…"
        case .ready: ""
        case .needsMigration: "Made with an older beads."
        case .needsNewerApp: "Made with a newer beads than this app."
        case .legacy: "Made with beads before 1.0."
        case .server: "Uses a Dolt server."
        case .failed: "Could not be opened."
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
        } else if let place = model.selection {
            switch place {
            case .ready, .project: ReadyView(model: model)
            case .needsYou: NeedsYouView(model: model)
            case .agents: AgentsView(model: model)
            case .workflows: WorkflowsView(model: model)
            case .activity: ActivityView(model: model)
            default: ContentUnavailableView(place.title, systemImage: place.symbol)
            }
        } else {
            ContentUnavailableView("No Selection", systemImage: "sidebar.left")
        }
    }
}
