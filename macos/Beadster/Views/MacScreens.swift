// Mac boards, part one: first run, Needs You, Ready with the bead inspector, Agents.
// Each view answers one question; the question sits above each view.
import SwiftUI

// "Get me from installed to my beads": one folder grant covers every project under it.
struct WelcomeBoard: View {
    var body: some View {
        MacWindow(place: "Ready", subtitle: "No folders yet", empty: true) {
            ContentUnavailableView {
                Label("Add a Folder", systemImage: "folder.badge.plus")
            } description: {
                Text("Choose the folder that holds your projects. Beadster finds every project with beads inside it and keeps access, so you choose once.")
            } actions: {
                Button("Choose Folder…") {}.buttonStyle(.borderedProminent).controlSize(.large)
            }
        }
    }
}

// "Which of these do I want to see?" — the sheet after the folder is chosen.
struct FoundSheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("6 Projects in Developer").font(.title2.weight(.semibold))
            Text("Beadster reads each one in place. Nothing is copied or uploaded.")
                .foregroundStyle(.secondary)
            List {
                ForEach(Sample.projects) { p in
                    Toggle(isOn: .constant(true)) {
                        HStack {
                            Label(p.name, systemImage: "folder")
                            Spacer()
                            Text("\(p.ready) ready").monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
                Toggle(isOn: .constant(false)) {
                    HStack {
                        Label("old-blog", systemImage: "folder")
                        Spacer()
                        Text("Needs beads 1.0").foregroundStyle(.orange)
                    }
                }
            }
            .listStyle(.bordered)
            .frame(height: 250)
            HStack {
                Spacer()
                Button("Cancel") {}.keyboardShortcut(.cancelAction)
                Button("Add 5 Projects") {}.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}

// "What is waiting on me?" — gates that need a person, then beads assigned to me.
struct NeedsYouBoard: View {
    var body: some View {
        MacWindow(place: "Needs You", subtitle: "2 approvals, 2 assigned") {
            List {
                Section("Approvals") {
                    ForEach(Sample.gates.filter(\.human)) { g in
                        HStack(spacing: 12) {
                            Image(systemName: "hand.raised.fill").foregroundStyle(.orange).font(.title3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(g.title).fontWeight(.medium)
                                Text("\(g.project) · \(g.molecule) · waiting \(g.since)").foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Reject") {}
                            Button("Approve") {}.buttonStyle(.borderedProminent)
                        }
                        .padding(.vertical, 6)
                    }
                }
                Section("Waiting on Something Else") {
                    ForEach(Sample.gates.filter { !$0.human }) { g in
                        HStack(spacing: 12) {
                            Image(systemName: "hourglass").foregroundStyle(.secondary).font(.title3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(g.title)
                                Text("\(g.project) · \(g.waitingFor)").foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(g.since).monospacedDigit().foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
                Section("Assigned to You") {
                    ForEach(Sample.assigned) { b in
                        HStack(spacing: 12) {
                            KindIcon(kind: b.kind).font(.title3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(b.title)
                                Text("\(b.project) · \(b.id)").foregroundStyle(.secondary)
                            }
                            Spacer()
                            PriorityLabel(p: b.priority)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }
}

// "What can be picked up next, across every project?"
struct ReadyTable: View {
    var body: some View {
        Table(Sample.ready, selection: .constant(Set(["wa-7f3a"]))) {
            TableColumn("") { b in KindIcon(kind: b.kind) }.width(24)
            TableColumn("Priority") { b in PriorityLabel(p: b.priority) }.width(56)
            TableColumn("Title") { b in Text(b.title) }
            TableColumn("Project") { b in Text(b.project) }.width(90)
            TableColumn("ID") { b in Text(b.id).monospaced().foregroundStyle(.secondary) }.width(64)
            TableColumn("Ready For") { b in Text(b.age).monospacedDigit() }.width(70)
        }
    }
}

struct ReadyBoard: View {
    var body: some View {
        MacWindow(place: "Ready", subtitle: "35 across 5 projects") {
            ReadyTable()
        } inspector: {
            BeadInspector(bead: Sample.detail)
        }
    }
}

// "What is this bead, what does it hold up, and what changed?"
struct BeadInspector: View {
    let bead: Bead
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(bead.title).font(.title3.weight(.semibold))
                    Text("\(bead.project) · \(bead.id)").foregroundStyle(.secondary)
                }
            }
            Section {
                LabeledContent("Status") { StatusLabel(status: bead.status) }
                Picker("Priority", selection: .constant(bead.priority)) {
                    ForEach(0..<5) { Text("P\($0)").tag($0) }
                }
                Picker("Type", selection: .constant("bug")) { Text("Bug").tag("bug") }
                Picker("Assignee", selection: .constant("none")) { Text("Anyone").tag("none") }
                LabeledContent("Labels", value: bead.labels.joined(separator: ", "))
            }
            Section("Holds Up") {
                Label("wa-91aa  Conflict banner copy", systemImage: "arrow.turn.down.right")
                Label("wa-5d02  Sync test for long notes", systemImage: "arrow.turn.down.right")
            }
            Section("Part Of") {
                LabeledContent("wa-e210  Sync 2.0") {
                    ProgressView(value: 0.6).frame(width: 80)
                }
            }
            Section("Description") {
                Text("Two devices edit the same note offline. After sync, the second paragraph of the older copy is gone. Repro steps in the linked note.")
            }
            Section("History") {
                LabeledContent("claude-review linked wa-91aa", value: "10:12")
                LabeledContent("anton set P0", value: "09:48")
                LabeledContent("claude-1 created it", value: "09:30")
            }
            Section {
                HStack {
                    Button("Claim") {}
                    Button("Close") {}
                    Spacer()
                    Button("Open in Terminal") {}
                }
            }
        }
        .formStyle(.grouped)
    }
}

// "What are my agents doing right now, and is any of them stuck?"
struct AgentsBoard: View {
    var body: some View {
        MacWindow(place: "Agents", subtitle: "4 working, 1 not answering") {
            Table(Sample.leases, selection: .constant(Set(["td-0b19"]))) {
                TableColumn("Agent") { l in
                    Label(l.agent, systemImage: l.healthy ? "circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(l.healthy ? Color.green : Color.orange)
                        .labelStyle(.titleAndIcon)
                }.width(130)
                TableColumn("Working On") { l in Text(l.bead.title) }
                TableColumn("Project") { l in Text(l.bead.project) }.width(90)
                TableColumn("Claimed") { l in Text(l.claimed).monospacedDigit() }.width(90)
                TableColumn("Last Heard") { l in
                    Text(l.heartbeat).monospacedDigit().foregroundStyle(l.healthy ? Color.primary : Color.orange)
                }.width(90)
            }
        } inspector: {
            LeaseInspector(lease: Sample.leases[2])
        }
    }
}

struct LeaseInspector: View {
    let lease: Lease
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Label("\(lease.agent) has gone quiet", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange).font(.headline)
                    Text("No heartbeat for \(lease.heartbeat.replacingOccurrences(of: " ago", with: "")). The claim ends in \(lease.expiresIn) and the bead goes back to Ready.")
                }
            }
            Section("Claim") {
                LabeledContent("Bead", value: "\(lease.bead.id)  \(lease.bead.title)")
                LabeledContent("Claimed", value: lease.claimed)
                LabeledContent("Last heartbeat", value: lease.heartbeat)
                LabeledContent("Ends in", value: lease.expiresIn)
            }
            Section("Last Changes by \(lease.agent)") {
                LabeledContent("notes edited", value: "11:18")
                LabeledContent("status open → in progress", value: "10:41")
            }
            Section {
                HStack {
                    Button("Release Now") {}
                    Button("Give More Time") {}
                }
            }
        }
        .formStyle(.grouped)
    }
}
