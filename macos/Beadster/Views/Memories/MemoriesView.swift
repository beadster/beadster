// "What do my agents remember about this project?" bd remember facts from every project:
// read, edit, forget.
import BeadsKit
import SwiftUI

struct MemoriesView: View {
    @Bindable var model: AppModel

    var body: some View {
        if model.memories.isEmpty {
            // U15 draws this empty state
            ContentUnavailableView("No Memories", systemImage: "brain",
                                   description: Text("Facts your agents save with bd remember show up here."))
        } else {
            Table(model.memories, selection: $model.selectedMemory) {
                TableColumn("Memory") { r in Text(r.memory.text).lineLimit(1) }.width(min: 240, ideal: 520)
                TableColumn("Project") { r in Text(r.project) }.width(min: 70, ideal: 100, max: 160)
                TableColumn("Key") { r in Text(r.memory.key).foregroundStyle(.secondary) }.width(min: 100, ideal: 180, max: 260)
            }
        }
    }
}

struct MemoryInspector: View {
    @Bindable var model: AppModel
    @State private var draft = ""

    var body: some View {
        if let row = model.memories.first(where: { $0.id == model.selectedMemory }) {
            Form {
                Section {
                    Text(row.memory.key).font(.headline).textSelection(.enabled)
                    TextEditor(text: $draft).font(.body).frame(minHeight: 120)
                        .accessibilityLabel("Memory text")
                }
                Section {
                    LabeledContent("Project", value: row.project)
                }
                Section {
                    HStack {
                        Button("Save") { Task { await model.saveMemory(row, text: draft) } }
                            .disabled(draft == row.memory.text || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Button("Forget") { Task { await model.forgetMemory(row) } }
                    }
                    if let error = model.lastError {
                        Text(error).foregroundStyle(Color.dangerInk).textSelection(.enabled)
                    }
                }
            }
            .formStyle(.grouped)
            .onAppear { draft = row.memory.text }
            .onChange(of: row.id) { _, _ in draft = row.memory.text }
        } else {
            ContentUnavailableView("No Selection", systemImage: "sidebar.right",
                                   description: Text("Select a memory to read or edit it."))
        }
    }
}
