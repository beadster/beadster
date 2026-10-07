import Foundation

/// A gate: a bead of type gate that holds other work until its condition clears.
public struct Gate: Identifiable, Hashable, Sendable {
    public var id: String { bead.id }
    public let bead: Bead
    /// The work waiting on this gate (its blocking dependents).
    public let holds: [LinkedBead]

    public enum Condition: Hashable, Sendable {
        /// A person decides: Approve or Reject.
        case human
        case timer(seconds: Int?)
        case pullRequest(String?)
        case run(String?)
        case bead(String?)
        case other(String)
    }

    public var condition: Condition {
        switch bead.awaitType ?? "" {
        case "human": .human
        case "timer": .timer(seconds: nil)
        case "gh:pr": .pullRequest(bead.awaitID)
        case "gh:run": .run(bead.awaitID)
        case "bead": .bead(bead.awaitID)
        case let other: .other(other)
        }
    }

    public var needsAPerson: Bool { condition == .human }

    /// What a person reads: the waiting work's title, or the gate's own when it holds nothing.
    public var title: String { holds.first?.title ?? bead.title }

    /// bd gate create --reason lands in the description as "Reason: …".
    public var reason: String? {
        guard let d = bead.description,
              let line = d.split(separator: "\n").last(where: { $0.hasPrefix("Reason: ") }) else { return nil }
        return String(line.dropFirst("Reason: ".count))
    }
}

extension Workspace {
    /// Open gates with the work each holds: one list, then one show per gate.
    public func gates() throws(BeadsError) -> [Gate] {
        let page = try send({ $0.filterType = "gate"; $0.includeGates = true; $0.limit = 0 }, op: "list")
        return try gates(among: page.issues ?? [])
    }

    /// The open gates among beads already read (a snapshot), each shown for the work it holds.
    public func gates(among beads: [Bead]) throws(BeadsError) -> [Gate] {
        var out: [Gate] = []
        for g in beads where g.type == .gate && g.status != .closed {
            let full = try show(g.id)
            out.append(Gate(bead: full, holds: full.holdsUp))
        }
        return out
    }

    /// Open beads assigned to this person.
    public func assigned(to person: String) throws(BeadsError) -> [Bead] {
        try list(BeadFilter(assignee: person, limit: 0)).beads.filter { $0.status != .closed }
    }
}

extension ProjectLibrary {
    public struct NeedsYou: Sendable {
        public var approvals: [(projectID: String, project: String, gate: Gate)] = []
        public var waiting: [(projectID: String, project: String, gate: Gate)] = []
        public var assigned: [(projectID: String, project: String, bead: Bead)] = []
        public var count: Int { approvals.count + assigned.count }
        public init() {}
    }

    /// What waits on this person in every open project: gates only a person can clear, gates
    /// waiting on something else (for context), and open beads assigned to them.
    public func needsYou(_ person: String) async -> NeedsYou {
        var out = NeedsYou()
        enum Item: Sendable { case gate(String, String, Gate), assigned(String, String, Bead) }
        await loadSnapshots()
        let items: [Item] = await eachOpen { entry, ws in
            let open = entry.snapshot ?? []
            // one show per open gate; everything else comes from the snapshot, no list call
            let gates = ((try? await ws.gates(among: open)) ?? []).map { Item.gate(entry.id, entry.found.name, $0) }
            let mine = open.filter { $0.assignee == person }.map { Item.assigned(entry.id, entry.found.name, $0) }
            return gates + mine
        }
        for item in items {
            switch item {
            case .gate(let id, let name, let gate):
                if gate.needsAPerson { out.approvals.append((id, name, gate)) } else { out.waiting.append((id, name, gate)) }
            case .assigned(let id, let name, let bead):
                out.assigned.append((id, name, bead))
            }
        }
        out.approvals.sort { $0.gate.bead.createdAt < $1.gate.bead.createdAt }
        out.assigned.sort { $0.bead.priority < $1.bead.priority }
        return out
    }
}
