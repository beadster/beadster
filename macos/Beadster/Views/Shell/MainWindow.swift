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
                    ContentUnavailableView("No Selection", systemImage: "sidebar.right")
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
    }

    private var subtitle: String {
        if model.loading { return "Opening projects…" }
        if model.entries.isEmpty { return "No folders yet" }
        let n = model.entries.count
        return "\(model.totalReady.formatted()) ready across \(n.formatted()) \(n == 1 ? "project" : "projects")"
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
                row(.needsYou)
                row(.ready, count: model.entries.isEmpty ? nil : model.totalReady)
                row(.agents)
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
        if model.loading && model.entries.isEmpty {
            ProgressView("Opening projects…")
        } else if !model.hasFolders {
            ContentUnavailableView {
                Label("Add a Folder", systemImage: "folder.badge.plus")
            } description: {
                Text("Choose the folder that holds your projects. Beadster finds every project with beads inside it and keeps access, so you choose once.")
            } actions: {
                Button("Choose Folder…") { Task { await model.addFolder() } }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        } else if let place = model.selection {
            ContentUnavailableView(place.title, systemImage: place.symbol)
        } else {
            ContentUnavailableView("No Selection", systemImage: "sidebar.left")
        }
    }
}
