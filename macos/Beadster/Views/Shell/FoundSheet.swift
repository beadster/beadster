// "Which of these do I want to see?": the projects found in a folder just chosen.
// HIG sheets.md: a title, one line of context, the default button trailing, Cancel beside it.
import BeadsKit
import SwiftUI

struct FoundSheet: View {
    @Bindable var model: AppModel

    var body: some View {
        if let pending = model.pending {
            VStack(alignment: .leading, spacing: 16) {
                Text(title(pending)).font(.title2.weight(.semibold))
                if !pending.found.isEmpty {
                    Text("beadster reads each one in place. Nothing is copied or uploaded.")
                        .foregroundStyle(.secondary)
                }
                if pending.found.isEmpty {
                    ContentUnavailableView {
                        Image(systemName: "folder")
                    } description: {
                        Text("No folder in here has beads. Choose the folder that holds your projects.")
                    }
                    .frame(height: 250)
                } else {
                    List {
                        ForEach(pending.found) { found in
                            row(found, state: pending.states[found.relativePath])
                        }
                    }
                    .listStyle(.bordered)
                    .frame(height: 250)
                }
                HStack {
                    Spacer()
                    Button("Cancel") { model.cancelPending() }
                        .keyboardShortcut(.cancelAction)
                    if pending.found.isEmpty {
                        Button("Choose Another Folder…") {
                            model.cancelPending()
                            Task { await model.chooseFolder() }
                        }
                        .keyboardShortcut(.defaultAction)
                    } else {
                        Button(addTitle(pending)) { Task { await model.confirmPending() } }
                            .keyboardShortcut(.defaultAction)
                            .disabled(pending.chosen.isEmpty)
                    }
                }
            }
            .padding(20)
            .frame(width: 520)
        }
    }

    private func title(_ p: AppModel.PendingFolder) -> String {
        let name = URL(fileURLWithPath: p.folder.path).lastPathComponent
        let n = p.found.count
        if n == 0 { return "No Projects in \(name)" }
        return "\(n.formatted()) \(n == 1 ? "Project" : "Projects") in \(name)"
    }

    private func addTitle(_ p: AppModel.PendingFolder) -> String {
        let n = p.chosen.count
        return "Add \(n.formatted()) \(n == 1 ? "Project" : "Projects")"
    }

    @ViewBuilder private func row(_ found: FoundProject, state: ProjectLibrary.State?) -> some View {
        let canOpen = found.kind == .embedded
        Toggle(isOn: binding(found.relativePath)) {
            HStack {
                Label(found.name, systemImage: "folder")
                Spacer()
                detail(state)
            }
        }
        .disabled(!canOpen)
    }

    @ViewBuilder private func detail(_ state: ProjectLibrary.State?) -> some View {
        switch state {
        case .ready(let n): Text("\(n.formatted()) ready").monospacedDigit().foregroundStyle(.secondary)
        case .legacy: Text("Needs beads 1.0").foregroundStyle(Color.warningInk)
        case .server: Text("Uses a Dolt server").foregroundStyle(.secondary)
        case .needsMigration: Text("Made with an older beads").foregroundStyle(Color.warningInk)
        case .needsNewerApp: Text("Needs a newer beadster").foregroundStyle(Color.warningInk)
        case .failed: Text("Can't be opened").foregroundStyle(Color.warningInk)
        case .opening, nil: ProgressView().controlSize(.small)
        }
    }

    private func binding(_ path: String) -> Binding<Bool> {
        Binding(
            get: { model.pending?.chosen.contains(path) ?? false },
            set: { on in
                if on { model.pending?.chosen.insert(path) } else { model.pending?.chosen.remove(path) }
            }
        )
    }
}
