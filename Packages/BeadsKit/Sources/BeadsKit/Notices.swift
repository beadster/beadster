import Foundation

/// Something worth a notification: what changed since the last look.
public struct Notice: Hashable, Sendable {
    public enum Kind: String, Sendable { case gate, quiet, assigned, closed }
    public let kind: Kind
    /// Stable per thing, so the same gate never notifies twice.
    public let id: String
    public let title: String
    public let body: String
    public let projectID: String
    public let beadID: String
}

/// What was true at the last look, enough to tell what is new.
public struct NoticeState: Sendable {
    var gates: Set<String> = []
    var quiet: Set<String> = []
    var assigned: Set<String> = []
    var closed: Set<String> = []
    var primed = false

    public init() {}

    /// Notices for what is new since the last call. The first call only takes the baseline:
    /// opening the app never announces what was already there.
    public mutating func update(needsYou: ProjectLibrary.NeedsYou,
                                working: [(projectID: String, project: String, bead: Bead)],
                                closedEvents: [ActivityItem], now: Date) -> [Notice] {
        var out: [Notice] = []
        let gateNow = Dictionary(needsYou.approvals.map { ("\($0.projectID)|\($0.gate.id)", $0) }, uniquingKeysWith: { a, _ in a })
        let quietNow = Dictionary(working.filter { ($0.bead.lease?.health(at: now) ?? .active) == .quiet }
            .map { ("\($0.projectID)|\($0.bead.id)", $0) }, uniquingKeysWith: { a, _ in a })
        let assignedNow = Dictionary(needsYou.assigned.map { ("\($0.projectID)|\($0.bead.id)", $0) }, uniquingKeysWith: { a, _ in a })
        let closedNow = Dictionary(closedEvents.filter { $0.event.kind == "closed" }.map { ("\($0.projectID)|\($0.event.beadID)", $0) },
                                   uniquingKeysWith: { a, _ in a })
        if primed {
            for (key, g) in gateNow where !gates.contains(key) {
                out.append(Notice(kind: .gate, id: key, title: "Waiting for your approval",
                                  body: [g.gate.title, g.gate.reason, g.project].compactMap { $0 }.joined(separator: " · "),
                                  projectID: g.projectID, beadID: g.gate.id))
            }
            for (key, w) in quietNow where !quiet.contains(key) {
                out.append(Notice(kind: .quiet, id: key, title: "\(w.bead.assignee ?? "An agent") has gone quiet",
                                  body: "\(w.bead.title) · \(w.project)", projectID: w.projectID, beadID: w.bead.id))
            }
            for (key, a) in assignedNow where !assigned.contains(key) {
                out.append(Notice(kind: .assigned, id: key, title: "Assigned to you",
                                  body: "\(a.bead.title) · \(a.project)", projectID: a.projectID, beadID: a.bead.id))
            }
            for (key, c) in closedNow where !closed.contains(key) {
                out.append(Notice(kind: .closed, id: key, title: "\(c.event.actor) closed a bead",
                                  body: [c.title, c.project].compactMap { $0 }.joined(separator: " · "),
                                  projectID: c.projectID, beadID: c.event.beadID))
            }
        }
        gates = Set(gateNow.keys)
        quiet = Set(quietNow.keys)
        assigned = Set(assignedNow.keys)
        closed.formUnion(closedNow.keys)
        primed = true
        return out.sorted { $0.id < $1.id }
    }
}
