// "What is this bead, what does it hold up, and what changed?" HIG: inspectors are a grouped
// form beside the content; edits apply as they are made.
import BeadsKit
import SwiftUI

struct BeadInspector: View {
    @Bindable var model: AppModel

    var body: some View {
        if let bead = model.inspected {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(bead.title).font(.title3.weight(.semibold))
                        Text("\(projectName) · \(bead.id)").foregroundStyle(.secondary)
                    }
                }
                Section {
                    LabeledContent("Status") { StatusText(status: bead.status) }
                    Picker("Priority", selection: Binding(get: { bead.priority }, set: { p in
                        Task { await model.write { ws, id, actor throws(BeadsError) in
                            var e = BeadEdit(); e.priority = p; try await ws.update(id, e, as: actor) } }
                    })) {
                        ForEach(0..<5) { Text("P\($0)").tag($0) }
                    }
                    Picker("Type", selection: Binding(get: { bead.type.rawValue }, set: { t in
                        Task { await model.write { ws, id, actor throws(BeadsError) in
                            var e = BeadEdit(); e.type = BeadType(rawValue: t); try await ws.update(id, e, as: actor) } }
                    })) {
                        ForEach(["task", "bug", "feature", "chore", "epic"], id: \.self) { Text($0.capitalized).tag($0) }
                        if !["task", "bug", "feature", "chore", "epic"].contains(bead.type.rawValue) {
                            Text(bead.type.rawValue.capitalized).tag(bead.type.rawValue)
                        }
                    }
                    LabeledContent("Assignee", value: bead.assignee ?? "Anyone")
                    if !bead.labels.isEmpty {
                        LabeledContent("Labels", value: bead.labels.joined(separator: ", "))
                    }
                }
                if !bead.holdsUp.isEmpty {
                    Section("Holds Up") {
                        ForEach(bead.holdsUp) { l in
                            Label("\(l.id)  \(l.title)", systemImage: "arrow.turn.down.right")
                        }
                    }
                }
                if let parent = bead.parentLink {
                    Section("Part Of") {
                        LabeledContent("\(parent.id)  \(parent.title)") { StatusText(status: parent.status) }
                    }
                }
                if let text = bead.description, !text.isEmpty {
                    Section("Description") { Text(text).textSelection(.enabled) }
                }
                if !model.inspectedHistory.isEmpty {
                    Section("History") {
                        ForEach(model.inspectedHistory.prefix(5)) { e in
                            LabeledContent(e.summary) {
                                Text(e.at, format: .relative(presentation: .named)).monospacedDigit()
                            }
                        }
                        Button("Show All Changes") {
                            if let row = model.readyRows.first(where: { $0.id == model.selectedRow }) {
                                Task { await model.showHistory(of: bead, in: row.projectID) }
                            }
                        }
                    }
                }
                Section {
                    HStack {
                        Button("Claim") {
                            Task { await model.write { ws, id, actor throws(BeadsError) in try await ws.claim(id, as: actor) } }
                        }
                        .disabled(bead.assignee != nil)
                        Button("Close") {
                            Task { await model.write { ws, id, actor throws(BeadsError) in try await ws.close(id, as: actor) } }
                        }
                    }
                    if let error = model.lastError {
                        Text(error).foregroundStyle(.red).textSelection(.enabled)
                    }
                }
            }
            .formStyle(.grouped)
        } else {
            ContentUnavailableView("No Selection", systemImage: "sidebar.right",
                                   description: Text("Select a bead to see it here."))
        }
    }

    private var projectName: String {
        model.readyRows.first { $0.id == model.selectedRow }?.project ?? ""
    }
}
