// "How far along is each piece of work, and where is it stuck?" Molecules and epics with
// their steps, who holds each step, and the gate a workflow waits on.
import BeadsKit
import SwiftUI

struct WorkflowsView: View {
    @Bindable var model: AppModel
    @State private var collapsed: Set<String> = []

    var body: some View {
        if let id = model.mapped, let row = model.workflows.first(where: { $0.id == id }) {
            MapView(row: row) { model.mapped = nil }
        } else if model.workflows.isEmpty {
            // U15 draws this empty state
            ContentUnavailableView("No Workflows", systemImage: "point.3.connected.trianglepath.dotted",
                                   description: Text("Epics and workflows poured from formulas show up here with their steps."))
        } else {
            List {
                ForEach(model.workflows) { row in
                    DisclosureGroup(isExpanded: Binding(get: { !collapsed.contains(row.id) },
                                                        set: { open in if open { collapsed.remove(row.id) } else { collapsed.insert(row.id) } })) {
                        ForEach(row.workflow.steps) { step in
                            StepRow(step: step, waitsOn: row.workflow.openBlockers(of: step).count)
                        }
                    } label: {
                        HStack(spacing: 10) {
                            StatusSymbol(status: row.workflow.root.status)
                            Text(row.workflow.root.title).fontWeight(.semibold)
                            Text(row.project).foregroundStyle(.secondary)
                            Spacer()
                            if row.workflow.total > 0 {
                                ProgressView(value: row.workflow.fraction).frame(width: 120)
                                    .accessibilityLabel("\(row.workflow.done) of \(row.workflow.total) steps done")
                            }
                            Text("\(row.workflow.done) of \(row.workflow.total)").monospacedDigit().foregroundStyle(.secondary)
                                .frame(width: 70, alignment: .trailing)
                            Button { model.mapped = row.id } label: {
                                Label("Show Map", systemImage: "point.3.filled.connected.trianglepath.dotted")
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .help("Show Map")
                            .accessibilityLabel("Show map of \(row.workflow.root.title)")
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
        }
    }
}

/// One step: its status (or the hand for a gate), its title, and who holds it.
struct StepRow: View {
    let step: Bead
    /// Open steps of the same workflow this one waits on.
    let waitsOn: Int

    var body: some View {
        HStack(spacing: 10) {
            if step.type == .gate && step.status != .closed {
                Image(systemName: "hand.raised.fill").foregroundStyle(.orange).accessibilityLabel("Gate")
            } else {
                StatusSymbol(status: step.status)
            }
            Text(step.title)
            Spacer()
            Text(who).foregroundStyle(isYours ? Color.orange : Color.secondary)
        }
        .padding(.vertical, 2)
    }

    private var isYours: Bool { step.type == .gate && step.awaitType == "human" && step.status != .closed }

    private var who: String {
        if isYours { return "you" }
        if let a = step.assignee, !a.isEmpty { return a }
        if step.status == .closed { return "done" }
        if waitsOn > 0 { return "waits on \(waitsOn)" }
        return step.status == .blocked ? "waiting" : "ready"
    }
}

/// Status as a symbol only, named for VoiceOver (rows carry the word elsewhere).
struct StatusSymbol: View {
    let status: BeadStatus
    var body: some View {
        StatusText(status: status).labelStyle(.iconOnly).accessibilityLabel(status.rawValue.replacingOccurrences(of: "_", with: " "))
    }
}
