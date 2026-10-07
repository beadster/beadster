// "Who changed this, and what was it before?" Dolt keeps every version of a bead; this is
// each field change between them, newest first. Restore writes an earlier version back as
// one more change, through beads: history is never rewritten.
import BeadsKit
import SwiftUI

struct HistoryView: View {
    @Bindable var model: AppModel
    let target: AppModel.HistoryTarget

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button { model.historyTarget = nil } label: { Label("Back", systemImage: "chevron.left") }
                    .buttonStyle(.borderless)
                Text("\(target.bead.title) · \(target.project) · \(target.bead.id)").foregroundStyle(.secondary).lineLimit(1)
                Spacer()
            }
            .padding([.horizontal, .top], 16).padding(.bottom, 8)
            if model.historyChanges.isEmpty {
                ContentUnavailableView("No Changes Yet", systemImage: "clock",
                                       description: Text("This bead is as it was created."))
            } else {
                Table(model.historyChanges, selection: $model.selectedChange) {
                    TableColumn("When") { c in
                        Text(c.at, format: .relative(presentation: .numeric, unitsStyle: .abbreviated)).monospacedDigit()
                    }
                    .width(min: 90, ideal: 120, max: 160)
                    TableColumn("Who") { c in Text(c.who) }.width(min: 70, ideal: 100, max: 140)
                    TableColumn("Field") { c in Text(c.field) }.width(min: 60, ideal: 90, max: 110)
                    TableColumn("Before") { c in
                        Text(c.before.isEmpty ? "—" : c.before).foregroundStyle(.secondary).strikethrough(!c.before.isEmpty).lineLimit(1)
                    }
                    TableColumn("After") { c in Text(c.after.isEmpty ? "—" : c.after).lineLimit(1) }
                }
            }
        }
    }
}

/// Beside the history: the bead before the selected change, and Restore This Version.
struct VersionInspector: View {
    @Bindable var model: AppModel

    var body: some View {
        if let v = model.versionBeforeSelected {
            Form {
                Section {
                    LabeledContent("Title", value: v.bead.title)
                    LabeledContent("Status") { StatusText(status: v.bead.status) }
                    LabeledContent("Priority") { PriorityText(priority: v.bead.priority) }
                    LabeledContent("Assignee", value: v.bead.assignee.flatMap { $0.isEmpty ? nil : $0 } ?? "Anyone")
                } header: {
                    Text("Before This Change, \(v.at.formatted(.relative(presentation: .named)))")
                }
                Section {
                    Button("Restore This Version") { Task { await model.restoreSelected() } }
                    if let error = model.lastError {
                        Text(error).foregroundStyle(.red).textSelection(.enabled)
                    }
                }
            }
            .formStyle(.grouped)
        } else {
            ContentUnavailableView("No Earlier Version", systemImage: "clock",
                                   description: Text("Select a change to see the bead before it."))
        }
    }
}
