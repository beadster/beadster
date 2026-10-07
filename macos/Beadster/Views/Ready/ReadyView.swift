// "What can be picked up next, across every project?" Ready work in bd ready's order
// (priority, then age), one table. HIG lists-and-tables: sortable columns, selection drives
// the inspector.
import BeadsKit
import SwiftUI

struct ReadyView: View {
    @Bindable var model: AppModel

    var body: some View {
        let rows = model.visibleReady
        if rows.isEmpty && !model.search.isEmpty {
            ContentUnavailableView.search(text: model.search)
        } else if rows.isEmpty {
            ContentUnavailableView("Nothing Ready", systemImage: "checkmark.circle",
                                   description: Text("Every open bead is waiting on something, or there is nothing open."))
        } else {
            Table(rows, selection: Binding(get: { model.selectedRow }, set: { id in Task { await model.inspect(id) } })) {
                TableColumn("") { r in KindSymbol(type: r.bead.type) }.width(24)
                TableColumn("Priority") { r in PriorityText(priority: r.bead.priority) }.width(56)
                TableColumn("Title") { r in Text(r.bead.title) }.width(min: 200, ideal: 380)
                TableColumn("Project") { r in Text(r.project) }.width(min: 80, ideal: 110, max: 160)
                TableColumn("ID") { r in Text(r.bead.id).foregroundStyle(.secondary) }.width(min: 60, ideal: 80, max: 110)
                TableColumn("Created") { r in Text(r.bead.createdAt, format: .relative(presentation: .named)).monospacedDigit() }
                    // "58 seconds ago" is the longest the column shows: it fits whole (the store shots cut it to "1 minute…")
                    .width(min: 110, ideal: 120, max: 150)
            }
        }
    }
}

/// The bead's type as a symbol, named for VoiceOver.
struct KindSymbol: View {
    let type: BeadType
    var body: some View {
        Image(systemName: symbol).foregroundStyle(.secondary).accessibilityLabel(type.rawValue)
    }
    private var symbol: String {
        switch type {
        case .bug: "ladybug"
        case .feature: "sparkles"
        case .epic: "square.stack.3d.up"
        case .chore: "wrench.adjustable"
        case .gate: "hand.raised"
        case .molecule: "point.3.connected.trianglepath.dotted"
        case .task, .decision, .message, .spike, .story, .milestone, .other: "checklist"
        }
    }
}

/// P0-P4: the number in mono, P0 red and P1 orange, the word always there (never colour alone).
struct PriorityText: View {
    let priority: Int
    var body: some View {
        Text("P\(priority)").monospacedDigit().fontWeight(priority <= 1 ? .semibold : .regular)
            .foregroundStyle(priority == 0 ? Color.dangerInk : priority == 1 ? Color.warningInk : Color.primary)
    }
}

/// Status as a symbol and a word.
struct StatusText: View {
    let status: BeadStatus
    var body: some View {
        Label(status.rawValue.replacingOccurrences(of: "_", with: " ").capitalized, systemImage: symbol)
            .foregroundStyle(tint)
    }
    private var symbol: String {
        switch status {
        case .open: "circle"
        case .inProgress: "circle.lefthalf.filled"
        case .blocked: "exclamationmark.circle"
        case .closed: "checkmark.circle.fill"
        case .deferred: "moon.circle"
        case .pinned: "pin.circle"
        case .hooked: "link.circle"
        case .other: "circle.dashed"
        }
    }
    private var tint: Color {
        switch status {
        case .inProgress: .blue
        case .blocked: .warningInk
        case .closed: .successInk
        default: .secondary
        }
    }
}
