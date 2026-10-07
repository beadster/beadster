import Foundation

/// A piece of work with steps: a molecule poured from a formula, or an epic with children.
public struct Workflow: Identifiable, Hashable, Sendable {
    public var id: String { root.id }
    public let root: Bead
    /// The steps, in beads' list order, closed ones included.
    public let steps: [Bead]

    public var isMolecule: Bool { root.type == .molecule }
    public var done: Int { steps.filter { $0.status == .closed }.count }
    public var total: Int { steps.count }
    public var fraction: Double { total == 0 ? 0 : Double(done) / Double(total) }
    /// Steps of this workflow that `step` waits on and that are not closed yet.
    public func openBlockers(of step: Bead) -> [Bead] {
        let blocking = Set(step.edges.filter { $0.kind.isBlocking }.map(\.dependsOnID))
        return steps.filter { blocking.contains($0.id) && $0.status != .closed }
    }

    /// The open gate among the steps, if the workflow is waiting on one.
    public var waitingGate: Bead? { steps.first { $0.type == .gate && $0.status != .closed } }
}

extension Workspace {
    /// Open molecules and epics with their steps: one list per kind, one list per workflow.
    public func workflows() throws(BeadsError) -> [Workflow] {
        var roots: [Bead] = []
        for type in ["molecule", "epic"] {
            roots += try send({ $0.filterType = type; $0.limit = 0 }, op: "list").issues ?? []
        }
        var out: [Workflow] = []
        for root in roots where root.status != .closed {
            let steps = try send({ $0.parent = root.id; $0.all = true; $0.includeGates = true; $0.limit = 0 }, op: "list").issues ?? []
            out.append(Workflow(root: root, steps: steps))
        }
        return out
    }
}

extension ProjectLibrary {
    public func workflowsEverywhere() async -> [(projectID: String, project: String, workflow: Workflow)] {
        let out: [(String, String, Workflow)] = await eachOpen { entry, ws in
            ((try? await ws.workflows()) ?? []).map { (entry.id, entry.found.name, $0) }
        }
        return out.sorted { $0.2.root.updatedAt > $1.2.root.updatedAt }
    }
}
