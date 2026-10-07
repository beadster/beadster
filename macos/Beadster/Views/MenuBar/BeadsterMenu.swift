// The menu bar extra: "anything for me?" without opening the window. HIG the-menu-bar: a
// menu, not a popover; the person turns it on in Settings.
import BeadsKit
import SwiftUI

struct BeadsterMenu: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let n = model.needsYou
        Section("Needs You") {
            if n.approvals.isEmpty {
                Text("Nothing waits on you")
            }
            ForEach(n.approvals, id: \.gate.id) { item in
                Menu("\(item.gate.title) · \(item.project)") {
                    Button("Approve") { Task { await model.decide(gate: item.gate, in: item.projectID, approve: true) } }
                    Button("Reject") { Task { await model.decide(gate: item.gate, in: item.projectID, approve: false) } }
                }
            }
        }
        if !model.working.isEmpty {
            Section("Agents") {
                ForEach(model.working.prefix(5)) { row in
                    Button {
                        open(.agents)
                    } label: {
                        let healthy = row.bead.lease?.health(at: .now) ?? .active
                        Label("\(row.bead.assignee ?? "Someone"): \(row.bead.title)",
                              systemImage: healthy == .active ? "circle.fill" : "exclamationmark.triangle.fill")
                    }
                }
            }
        }
        Divider()
        Button("\(model.totalReady.formatted()) Ready") { open(.ready) }
        Button("Open beadster") { open(model.selection ?? .ready) }
            .keyboardShortcut("o")
    }

    private func open(_ place: Place) {
        model.selection = place
        openWindow(id: "main")
        NSApp.activate()
    }
}

/// The icon in the menu bar: a raised hand when something waits on you.
struct BeadsterMenuLabel: View {
    let model: AppModel
    var body: some View {
        let count = model.needsYou.approvals.count
        if count > 0 {
            Label("\(count) waiting", systemImage: "hand.raised.fill")
        } else {
            Label("beadster", systemImage: "circle.hexagongrid")
        }
    }
}
