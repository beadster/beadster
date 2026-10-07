// Sample data for 2.0 until BeadsKit lands (K1-K3). Same shapes as scripts/render-design/Data.swift, the boards.
// hash ids per project prefix, priorities 0-4, types, statuses, work leases, gates, memories.
import SwiftUI

enum Status: String { case open, inProgress = "in progress", blocked, closed, deferred }
enum Kind: String { case task, bug, feature, epic, chore, gate }

struct Project: Identifiable, Hashable {
    let id: String
    let name: String
    let prefix: String
    let ready: Int
    let mode: String
}

struct Bead: Identifiable, Hashable {
    let id: String
    let title: String
    let project: String
    var status: Status = .open
    var kind: Kind = .task
    var priority: Int = 2
    var assignee: String = ""
    var age: String = ""
    var blockedBy: [String] = []
    var blocks: [String] = []
    var parent: String = ""
    var labels: [String] = []
}

struct Lease: Identifiable {
    var id: String { bead.id }
    let bead: Bead
    let agent: String
    let claimed: String
    let heartbeat: String
    let expiresIn: String
    let healthy: Bool
}

struct Gate: Identifiable {
    let id: String
    let title: String
    let project: String
    let waitingFor: String
    let since: String
    let molecule: String
    let human: Bool
}

struct Event: Identifiable {
    let id = UUID()
    let time: String
    let who: String
    let verb: String
    let bead: String
    let title: String
    let detail: String
    let commit: String
}

struct Memory: Identifiable {
    var id: String { key }
    let key: String
    let project: String
    let text: String
    let saved: String
}

enum Sample {
    static let projects = [
        Project(id: "tinydot", name: "tinydot", prefix: "td", ready: 7, mode: "Embedded"),
        Project(id: "wander", name: "wander", prefix: "wa", ready: 12, mode: "Embedded"),
        Project(id: "deepcalc", name: "deepcalc", prefix: "dc", ready: 9, mode: "Server"),
        Project(id: "superclock", name: "superclock", prefix: "sc", ready: 4, mode: "Embedded"),
        Project(id: "bloodwork", name: "bloodwork", prefix: "bw", ready: 3, mode: "Embedded"),
    ]

    static let ready: [Bead] = [
        Bead(id: "wa-7f3a", title: "Sync conflicts lose the second paragraph", project: "wander", kind: .bug, priority: 0, age: "2 h", labels: ["sync"]),
        Bead(id: "dc-1c9e", title: "Formula bar drops the cursor after undo", project: "deepcalc", kind: .bug, priority: 1, age: "40 min"),
        Bead(id: "td-4f2a", title: "Custom domain check times out on .dev", project: "tinydot", kind: .bug, priority: 1, age: "5 h", labels: ["domains"]),
        Bead(id: "sc-02d1", title: "Timer widget for the Lock Screen", project: "superclock", kind: .feature, priority: 2, age: "1 d", parent: "sc-e100"),
        Bead(id: "wa-88b0", title: "Backlinks panel: group by note", project: "wander", kind: .feature, priority: 2, age: "3 h", parent: "wa-e210"),
        Bead(id: "dc-5a10", title: "Insights tab: explain a jump", project: "deepcalc", kind: .task, priority: 2, age: "20 min", parent: "dc-e300"),
        Bead(id: "bw-3b77", title: "Read RDW from the PDF table", project: "bloodwork", kind: .task, priority: 2, age: "2 d"),
        Bead(id: "td-9e01", title: "Move the editor to the shared toolbar", project: "tinydot", kind: .chore, priority: 3, age: "4 d"),
        Bead(id: "wa-2c4d", title: "Write the iCloud migration note", project: "wander", kind: .task, priority: 3, age: "6 d"),
    ]

    static let detail = Bead(id: "wa-7f3a", title: "Sync conflicts lose the second paragraph", project: "wander",
                             status: .open, kind: .bug, priority: 0, assignee: "", age: "2 h",
                             blockedBy: [], blocks: ["wa-91aa", "wa-5d02"], parent: "wa-e210", labels: ["sync", "data-loss"])

    static let leases: [Lease] = [
        Lease(bead: Bead(id: "dc-77c2", title: "Branch mode: keep edits off the main sheet", project: "deepcalc", status: .inProgress, kind: .feature, priority: 1),
              agent: "claude-1", claimed: "18 min ago", heartbeat: "9 s ago", expiresIn: "4 min", healthy: true),
        Lease(bead: Bead(id: "wa-61f0", title: "Outline view: drag to reorder headings", project: "wander", status: .inProgress, kind: .feature, priority: 2),
              agent: "codex", claimed: "42 min ago", heartbeat: "14 s ago", expiresIn: "5 min", healthy: true),
        Lease(bead: Bead(id: "td-0b19", title: "Billing page: show the next invoice", project: "tinydot", status: .inProgress, kind: .task, priority: 2),
              agent: "claude-2", claimed: "1 h ago", heartbeat: "4 min ago", expiresIn: "45 s", healthy: false),
        Lease(bead: Bead(id: "sc-4a4a", title: "Alarm sound picker on iPad", project: "superclock", status: .inProgress, kind: .bug, priority: 1),
              agent: "claude-review", claimed: "6 min ago", heartbeat: "3 s ago", expiresIn: "5 min", healthy: true),
    ]

    static let gates: [Gate] = [
        Gate(id: "td-g812", title: "Deploy tinydot.com to production", project: "tinydot", waitingFor: "Your approval", since: "12 min", molecule: "release 2.4", human: true),
        Gate(id: "wa-g233", title: "Ship the vault migration to beta", project: "wander", waitingFor: "Your approval", since: "1 h", molecule: "beta 3.1", human: true),
        Gate(id: "dc-g090", title: "CI on PR #233", project: "deepcalc", waitingFor: "GitHub Actions", since: "4 min", molecule: "many cursors", human: false),
        Gate(id: "sc-g014", title: "App Review for 2.1", project: "superclock", waitingFor: "Timer, 2 d left", since: "1 d", molecule: "release 2.1", human: false),
    ]

    static let assigned: [Bead] = [
        Bead(id: "bw-9001", title: "Pick the words for the RDW explainer", project: "bloodwork", kind: .task, priority: 1, assignee: "anton", age: "1 d"),
        Bead(id: "dc-3d3d", title: "Decide: Insights on by default?", project: "deepcalc", kind: .task, priority: 2, assignee: "anton", age: "3 h"),
    ]

    static let events: [Event] = [
        Event(time: "11:42", who: "claude-1", verb: "closed", bead: "dc-1b20", title: "Cursor colour per agent", detail: "in progress → closed", commit: "8q1v2c0"),
        Event(time: "11:40", who: "claude-1", verb: "created", bead: "dc-1c9e", title: "Formula bar drops the cursor after undo", detail: "discovered from dc-1b20", commit: "u7mk3a1"),
        Event(time: "11:31", who: "codex", verb: "claimed", bead: "wa-61f0", title: "Outline view: drag to reorder headings", detail: "lease 5 min", commit: "c0lh9e4"),
        Event(time: "11:18", who: "claude-2", verb: "updated", bead: "td-0b19", title: "Billing page: show the next invoice", detail: "notes edited", commit: "3n2ba8f"),
        Event(time: "10:57", who: "anton", verb: "approved", bead: "sc-g013", title: "TestFlight build 214", detail: "gate resolved", commit: "kk02x1d"),
        Event(time: "10:12", who: "claude-review", verb: "linked", bead: "wa-7f3a", title: "Sync conflicts lose the second paragraph", detail: "blocks wa-91aa", commit: "p4r7v0s"),
    ]

    static let memories: [Memory] = [
        Memory(key: "deploy-only-npm-run-deploy", project: "tinydot", text: "Never run wrangler deploy. Always npm run deploy: it runs tests and typecheck first.", saved: "Sep 12"),
        Memory(key: "vault-history-stays-inside", project: "wander", text: "History lives in .wander inside the vault. Never move it out, iCloud sync depends on it.", saved: "Sep 30"),
        Memory(key: "ironcalc-patches", project: "deepcalc", text: "12 patches on top of upstream ironcalc 0.8.3. Re-apply them in order after every bump.", saved: "Oct 2"),
        Memory(key: "medical-words-reviewed", project: "bloodwork", text: "Every explainer sentence is reviewed by anton. Never invent a medical fact.", saved: "Oct 3"),
        Memory(key: "simulator-light-reboot", project: "superclock", text: "Light appearance in the simulator needs shutdown + boot before shots.", saved: "Oct 1"),
    ]
}

extension Bead {
    var projectName: String { project }
    var priorityLabel: String { "P\(priority)" }
}

/// Status as a symbol and a word, never colour alone.
struct StatusLabel: View {
    let status: Status
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
            Text(status.rawValue.capitalized)
        }
        .foregroundStyle(tint)
    }
    var symbol: String {
        switch status {
        case .open: "circle"
        case .inProgress: "circle.lefthalf.filled"
        case .blocked: "exclamationmark.circle"
        case .closed: "checkmark.circle.fill"
        case .deferred: "moon.circle"
        }
    }
    var tint: Color {
        switch status {
        case .open: .secondary
        case .inProgress: .blue
        case .blocked: .orange
        case .closed: .green
        case .deferred: .secondary
        }
    }
}

struct PriorityLabel: View {
    let p: Int
    var body: some View {
        Text("P\(p)").monospacedDigit().fontWeight(p <= 1 ? .semibold : .regular)
            .foregroundStyle(p == 0 ? Color.red : p == 1 ? Color.orange : Color.primary)
    }
}

struct KindIcon: View {
    let kind: Kind
    var body: some View {
        Image(systemName: symbol).foregroundStyle(.secondary).accessibilityLabel(kind.rawValue)
    }
    var symbol: String {
        switch kind {
        case .bug: "ladybug"
        case .feature: "sparkles"
        case .epic: "square.stack.3d.up"
        case .chore: "wrench.adjustable"
        case .gate: "hand.raised"
        case .task: "checklist"
        }
    }
}
