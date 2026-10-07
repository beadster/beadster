// Settings: the folders beadster may read, when to tell you, and your name in beads.
// HIG settings.md: a grouped form, changes apply at once, no Save button.
import BeadsKit
import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    @AppStorage("actorName") private var actorName = ""
    @AppStorage("notify.gates") private var notifyGates = true
    @AppStorage("notify.quiet") private var notifyQuiet = true
    @AppStorage("notify.assigned") private var notifyAssigned = true
    @AppStorage("notify.closed") private var notifyClosed = false
    @AppStorage("menuBarExtra") private var menuBarExtra = false

    var body: some View {
        Form {
            Section {
                ForEach(model.folders.folders) { folder in
                    FolderRow(folder: folder, health: model.folders.health(of: folder),
                              projects: model.projectCount(in: folder)) {
                        Task { await model.removeFolder(folder) }
                    }
                }
            } header: {
                Text("Folders")
            } footer: {
                HStack {
                    Button("Add Folder…") { Task { await model.chooseFolder() } }
                    Spacer()
                }
            }
            Section {
                Toggle("Show in the menu bar", isOn: $menuBarExtra)
            } footer: {
                Text("Approvals and your agents, one click away.").foregroundStyle(.secondary)
            }
            Section("Tell Me When") {
                Toggle("A gate needs my approval", isOn: $notifyGates)
                Toggle("An agent goes quiet", isOn: $notifyQuiet)
                Toggle("A bead is assigned to me", isOn: $notifyAssigned)
                Toggle("Work is closed", isOn: $notifyClosed)
            }
            Section {
                TextField("Your name in beads", text: $actorName, prompt: Text(NSUserName()))
            } header: {
                Text("You")
            } footer: {
                Text("Beads you create, claim or close carry this name.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct FolderRow: View {
    let folder: GrantedFolder
    let health: GrantedFolder.Health
    let projects: Int
    let remove: () -> Void

    var body: some View {
        LabeledContent {
            HStack(spacing: 12) {
                switch health {
                case .ok:
                    Text("\(projects.formatted()) \(projects == 1 ? "project" : "projects")").foregroundStyle(.secondary)
                case .moved(let to):
                    Label("Moved to \(URL(fileURLWithPath: to).lastPathComponent)", systemImage: "arrow.turn.up.right")
                        .foregroundStyle(.orange)
                case .missing:
                    Label("Can't be found", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                Button("Remove", action: remove)
            }
        } label: {
            Text(URL(fileURLWithPath: folder.path).lastPathComponent)
                .help(folder.path)
        }
    }
}
