// The window every board shares: sidebar of collections and projects, a content column, an
// optional inspector. HIG: sidebars.md (top-level collections, badges for counts),
// toolbars.md (title leading, actions and search trailing), split-views.md.
import SwiftUI

enum Place: String, Hashable {
    case needs = "Needs You", ready = "Ready", agents = "Agents", blocked = "Blocked", activity = "Activity"
    case memories = "Memories", workflows = "Workflows"
    case project = "Project"
}

struct Sidebar: View {
    @State var selection: String
    var empty = false
    var body: some View {
        List(selection: .constant(Optional(selection))) {
            Section {
                row("Needs You", "hand.raised", empty ? nil : 4)
                row("Ready", "checkmark.circle", empty ? nil : 35)
                row("Agents", "person.2.wave.2", empty ? nil : 4)
                row("Blocked", "exclamationmark.circle", empty ? nil : 6)
                row("Activity", "clock.arrow.circlepath", nil)
            }
            Section("Library") {
                row("Workflows", "point.3.connected.trianglepath.dotted", nil)
                row("Memories", "brain", nil)
            }
            if !empty {
                Section("Projects") {
                    ForEach(Sample.projects) { p in row(p.name, "folder", p.ready) }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(220)
    }

    @ViewBuilder func row(_ title: String, _ symbol: String, _ badge: Int?) -> some View {
        if let badge {
            Label(title, systemImage: symbol).badge(badge).tag(title)
        } else {
            Label(title, systemImage: symbol).tag(title)
        }
    }
}

struct MacWindow<Content: View, Inspector: View>: View {
    let place: String
    let subtitle: String
    @ViewBuilder let content: Content
    @ViewBuilder let inspector: Inspector
    var showInspector = true
    var empty = false

    var body: some View {
        NavigationSplitView {
            Sidebar(selection: place, empty: empty)
        } detail: {
            content
                .inspector(isPresented: .constant(showInspector)) {
                    inspector.inspectorColumnWidth(min: 300, ideal: 320)
                }
        }
        .navigationTitle(place)
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Button("All Projects") {}
                    Divider()
                    ForEach(Sample.projects) { p in Button(p.name) {} }
                } label: { Label("Filter", systemImage: "line.3.horizontal.decrease") }
                Button {} label: { Label("New Bead", systemImage: "plus") }
            }
        }
        .searchable(text: .constant(""), prompt: "Search beads")
    }
}

extension MacWindow where Inspector == EmptyView {
    init(place: String, subtitle: String, empty: Bool = false, @ViewBuilder content: () -> Content) {
        self.empty = empty
        self.place = place
        self.subtitle = subtitle
        self.content = content()
        self.inspector = EmptyView()
        self.showInspector = false
    }
}
