// Mac boards, part two: workflows, the dependency map, activity, a bead's history, memories,
// Settings and the menu bar panel.
import SwiftUI

struct Step: Identifiable {
    let id: String
    let title: String
    let status: Status
    let who: String
    var gate = false
    var children: [Step]? = nil
}

// "How far along is each piece of work, and where is it stuck?"
struct WorkflowsBoard: View {
    let steps: [Step] = [
        Step(id: "td-m24", title: "release 2.4 (from formula release)", status: .inProgress, who: "4 of 6", children: [
            Step(id: "td-m24.1", title: "Bump version and changelog", status: .closed, who: "claude-1"),
            Step(id: "td-m24.2", title: "Run the full test suite", status: .closed, who: "claude-1"),
            Step(id: "td-m24.3", title: "Build and upload to staging", status: .closed, who: "claude-2"),
            Step(id: "td-m24.4", title: "Smoke test staging", status: .closed, who: "claude-review"),
            Step(id: "td-g812", title: "Approve production deploy", status: .blocked, who: "you", gate: true),
            Step(id: "td-m24.6", title: "Deploy and watch the logs", status: .open, who: "after approval"),
        ]),
        Step(id: "wa-e210", title: "Sync 2.0", status: .inProgress, who: "6 of 10", children: [
            Step(id: "wa-7f3a", title: "Sync conflicts lose the second paragraph", status: .open, who: "ready"),
            Step(id: "wa-61f0", title: "Outline view: drag to reorder headings", status: .inProgress, who: "codex"),
            Step(id: "wa-91aa", title: "Conflict banner copy", status: .blocked, who: "waits on wa-7f3a"),
        ]),
        Step(id: "dc-e300", title: "Many cursors", status: .inProgress, who: "3 of 8", children: nil),
    ]

    var body: some View {
        MacWindow(place: "Workflows", subtitle: "3 running") {
            List {
                ForEach(steps) { top in
                    DisclosureGroup(isExpanded: .constant(top.children != nil)) {
                        ForEach(top.children ?? []) { s in row(s) }
                    } label: { row(top) }
                }
            }
        }
    }

    func row(_ s: Step) -> some View {
                    HStack(spacing: 10) {
                        if s.gate {
                            Image(systemName: "hand.raised.fill").foregroundStyle(.orange)
                        } else {
                            Image(systemName: StatusLabel(status: s.status).symbol)
                                .foregroundStyle(StatusLabel(status: s.status).tint)
                        }
                        Text(s.title).fontWeight(s.children != nil ? .semibold : .regular)
                        Spacer()
                        if s.children != nil {
                            ProgressView(value: progress(s)).frame(width: 120)
                        }
                        Text(s.who).foregroundStyle(s.gate ? Color.orange : Color.secondary)
                            .frame(width: 110, alignment: .trailing)
                    }
                    .padding(.vertical, 3)
    }

    func progress(_ s: Step) -> Double {
        let parts = s.who.split(separator: " ")
        guard parts.count == 3, let a = Double(parts[0]), let b = Double(parts[2]) else { return 0 }
        return a / b
    }
}

// "What holds what up?" — the epic as a map, drawn with Canvas.
struct GraphBoard: View {
    struct Node { let id: String; let title: String; let status: Status; let x: CGFloat; let y: CGFloat }
    let nodes: [Node] = [
        Node(id: "wa-e210", title: "Sync 2.0", status: .inProgress, x: 0.5, y: 0.1),
        Node(id: "wa-7f3a", title: "Conflicts lose a paragraph", status: .open, x: 0.2, y: 0.38),
        Node(id: "wa-61f0", title: "Drag to reorder", status: .inProgress, x: 0.5, y: 0.38),
        Node(id: "wa-3e3e", title: "Merge by block id", status: .closed, x: 0.8, y: 0.38),
        Node(id: "wa-91aa", title: "Conflict banner copy", status: .blocked, x: 0.12, y: 0.68),
        Node(id: "wa-5d02", title: "Sync test, long notes", status: .blocked, x: 0.36, y: 0.68),
        Node(id: "wa-g233", title: "Approve beta", status: .blocked, x: 0.62, y: 0.9),
    ]
    let edges = [("wa-e210", "wa-7f3a"), ("wa-e210", "wa-61f0"), ("wa-e210", "wa-3e3e"),
                 ("wa-7f3a", "wa-91aa"), ("wa-7f3a", "wa-5d02"), ("wa-91aa", "wa-g233"),
                 ("wa-5d02", "wa-g233"), ("wa-61f0", "wa-g233")]

    var body: some View {
        MacWindow(place: "wander", subtitle: "Sync 2.0 · map") {
            GeometryReader { geo in
                let size = geo.size
                ZStack {
                    Canvas { ctx, sz in
                        for (a, b) in edges {
                            guard let p = point(a, sz), let q = point(b, sz) else { continue }
                            var path = Path()
                            path.move(to: p)
                            path.addCurve(to: q, control1: CGPoint(x: p.x, y: (p.y + q.y) / 2), control2: CGPoint(x: q.x, y: (p.y + q.y) / 2))
                            ctx.stroke(path, with: .color(.secondary.opacity(0.6)), lineWidth: 1.5)
                        }
                    }
                    ForEach(nodes, id: \.id) { n in
                        let s = StatusLabel(status: n.status)
                        VStack(alignment: .leading, spacing: 3) {
                            Label(n.title, systemImage: n.id.contains("g") && n.id.hasSuffix("233") ? "hand.raised.fill" : s.symbol)
                                .foregroundStyle(.primary)
                            Text("\(n.id) · \(n.status.rawValue)").font(.callout).foregroundStyle(s.tint)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(.background, in: .rect(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(n.id == "wa-7f3a" ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: n.id == "wa-7f3a" ? 2 : 1))
                        .position(x: n.x * size.width, y: 30 + n.y * (size.height - 70))
                    }
                }
            }
            .padding(24)
        }
    }

    func point(_ id: String, _ sz: CGSize) -> CGPoint? {
        guard let n = nodes.first(where: { $0.id == id }) else { return nil }
        return CGPoint(x: n.x * sz.width, y: 30 + n.y * (sz.height - 70))
    }
}

// "What changed since I last looked?" — the events journal, newest first.
struct ActivityBoard: View {
    var body: some View {
        MacWindow(place: "Activity", subtitle: "Since 09:00 today") {
            List {
                Section("Today") {
                    ForEach(Sample.events) { e in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(e.time).monospacedDigit().foregroundStyle(.secondary).frame(width: 44, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(Text("\(e.who) \(e.verb)").fontWeight(.semibold)) \(e.title)")
                                Text("\(e.bead) · \(e.detail)").foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(e.commit).monospaced().foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }
}

// "Who changed this, and what was it before?" — Dolt keeps every cell's history.
struct HistoryBoard: View {
    struct Change: Identifiable { let id = UUID(); let field: String; let before: String; let after: String; let who: String; let when: String }
    let changes = [
        Change(field: "status", before: "open", after: "in progress", who: "claude-2", when: "10:41"),
        Change(field: "notes", before: "Show the plan name", after: "Show the plan name and the next invoice date", who: "claude-2", when: "11:18"),
        Change(field: "priority", before: "P3", after: "P2", who: "anton", when: "Yesterday"),
        Change(field: "assignee", before: "", after: "claude-2", who: "claude-2", when: "10:41"),
        Change(field: "title", before: "Billing page tweaks", after: "Billing page: show the next invoice", who: "anton", when: "Mon"),
    ]
    var body: some View {
        MacWindow(place: "tinydot", subtitle: "td-0b19 · History") {
            Table(changes) {
                TableColumn("When") { c in Text(c.when).monospacedDigit() }.width(80)
                TableColumn("Who") { c in Text(c.who) }.width(90)
                TableColumn("Field") { c in Text(c.field) }.width(80)
                TableColumn("Before") { c in Text(c.before.isEmpty ? "—" : c.before).foregroundStyle(.secondary).strikethrough(!c.before.isEmpty) }
                TableColumn("After") { c in Text(c.after) }
            }
        } inspector: {
            Form {
                Section("As of 10:40") {
                    LabeledContent("Status", value: "Open")
                    LabeledContent("Priority", value: "P2")
                    LabeledContent("Assignee", value: "Anyone")
                }
                Section { Button("Restore This Version") {} }
            }
            .formStyle(.grouped)
        }
    }
}

// "What do my agents remember about this project?" — bd remember, readable and editable.
struct MemoriesBoard: View {
    var body: some View {
        MacWindow(place: "Memories", subtitle: "5 across 5 projects") {
            Table(Sample.memories, selection: .constant(Set(["vault-history-stays-inside"]))) {
                TableColumn("Memory") { m in Text(m.text).lineLimit(1) }
                TableColumn("Project") { m in Text(m.project) }.width(90)
                TableColumn("Saved") { m in Text(m.saved).monospacedDigit() }.width(60)
            }
        } inspector: {
            Form {
                Section {
                    Text("vault-history-stays-inside").font(.headline)
                    Text(Sample.memories[1].text)
                }
                Section {
                    LabeledContent("Project", value: "wander")
                    LabeledContent("Saved by", value: "claude-1, Sep 30")
                    LabeledContent("Recalled", value: "14 times")
                }
                Section { HStack { Button("Edit") {}; Button("Forget") {} } }
            }
            .formStyle(.grouped)
        }
    }
}

// Settings: the folders Beadster may read, and when to tell you.
struct SettingsBoard: View {
    var body: some View {
        TabView {
            Form {
                Section {
                    LabeledContent("Developer") { Text("5 projects").foregroundStyle(.secondary) }
                    LabeledContent("Dropbox › systemoperator") { Text("4 projects").foregroundStyle(.secondary) }
                    LabeledContent("old-work") { Label("Folder moved", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                } header: {
                    Text("Folders")
                } footer: {
                    HStack { Button("Add Folder…") {}; Spacer() }
                }
                Section("Tell Me When") {
                    Toggle("A gate needs my approval", isOn: .constant(true))
                    Toggle("An agent goes quiet", isOn: .constant(true))
                    Toggle("A bead is assigned to me", isOn: .constant(true))
                    Toggle("Work is closed", isOn: .constant(false))
                }
                Section("You") {
                    TextField("Your name in beads", text: .constant("anton"))
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 560, height: 520)
    }
}

// The menu bar panel: "anything for me?" without opening the window.
struct MenuBarPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Needs You").font(.headline).padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 6)
            ForEach(Sample.gates.filter(\.human)) { g in
                HStack {
                    Image(systemName: "hand.raised.fill").foregroundStyle(.orange)
                    VStack(alignment: .leading) {
                        Text(g.title)
                        Text(g.project).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Approve") {}
                }
                .padding(.horizontal, 14).padding(.vertical, 6)
            }
            Divider().padding(.vertical, 6)
            Text("Agents").font(.headline).padding(.horizontal, 14).padding(.bottom, 4)
            ForEach(Sample.leases.prefix(3)) { l in
                HStack {
                    Image(systemName: l.healthy ? "circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(l.healthy ? Color.green : Color.orange).font(.caption)
                    Text(l.agent).frame(width: 96, alignment: .leading)
                    Text(l.bead.title).lineLimit(1).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14).padding(.vertical, 3)
            }
            Divider().padding(.vertical, 6)
            HStack {
                Text("35 ready").monospacedDigit().foregroundStyle(.secondary)
                Spacer()
                Button("Open Beadster") {}
            }
            .padding(.horizontal, 14).padding(.bottom, 12)
        }
        .frame(width: 380)
    }
}
