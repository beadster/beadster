import Foundation

/// A new bead. Only the title is required; beads defaults the rest (task, P2, open).
public struct NewBead: Sendable {
    public var title: String
    public var description: String?
    public var type: BeadType?
    public var priority: Int?
    public var assignee: String?
    public var parent: String?

    public init(title: String, description: String? = nil, type: BeadType? = nil, priority: Int? = nil,
                assignee: String? = nil, parent: String? = nil) {
        self.title = title
        self.description = description
        self.type = type
        self.priority = priority
        self.assignee = assignee
        self.parent = parent
    }
}

/// The fields one edit changes; nil leaves a field as it is.
public struct BeadEdit: Sendable {
    public var title: String?
    public var description: String?
    public var design: String?
    public var acceptanceCriteria: String?
    public var notes: String?
    public var status: BeadStatus?
    public var priority: Int?
    public var type: BeadType?
    public var assignee: String?
    public var addLabels: [String] = []
    public var removeLabels: [String] = []
    /// The edit lands only if the bead still has this status (else `.conflict`).
    public var ifStatus: BeadStatus?
    /// The edit lands only if the bead is still assigned to this ("" = unassigned).
    public var ifAssignee: String?

    public init() {}
}

/// Every write names who made it: the person's name in beads (Settings › You).
extension Workspace {
    @discardableResult
    public func create(_ new: NewBead, as actor: String) throws(BeadsError) -> Bead {
        let r = try send({
            $0.actor = actor
            $0.title = new.title
            $0.description = new.description
            $0.issueType = new.type?.rawValue
            $0.priority = new.priority
            $0.assignee = new.assignee
            $0.parent = new.parent
        }, op: "create")
        guard let bead = r.issue else { throw .undecodable("create answered without a bead") }
        return bead
    }

    @discardableResult
    public func update(_ id: String, _ edit: BeadEdit, as actor: String) throws(BeadsError) -> Bead? {
        try send({
            $0.actor = actor
            $0.id = id
            $0.title = edit.title
            $0.description = edit.description
            $0.design = edit.design
            $0.acceptance = edit.acceptanceCriteria
            $0.notes = edit.notes
            $0.newStatus = edit.status?.rawValue
            $0.priority = edit.priority
            $0.issueType = edit.type?.rawValue
            $0.assignee = edit.assignee
            $0.addLabels = edit.addLabels.isEmpty ? nil : edit.addLabels
            $0.removeLabels = edit.removeLabels.isEmpty ? nil : edit.removeLabels
            $0.expectedStatus = edit.ifStatus?.rawValue
            $0.expectedAssignee = edit.ifAssignee
        }, op: "update").issue
    }

    public func close(_ id: String, reason: String? = nil, as actor: String) throws(BeadsError) {
        _ = try send({ $0.actor = actor; $0.id = id; $0.reason = reason }, op: "close_issue")
    }

    public func reopen(_ id: String, reason: String? = nil, as actor: String) throws(BeadsError) {
        _ = try send({ $0.actor = actor; $0.id = id; $0.reason = reason }, op: "reopen")
    }

    /// Claims the bead for `actor` (assignee + in progress). Someone else's claim throws `.claimed`.
    public func claim(_ id: String, as actor: String) throws(BeadsError) {
        _ = try send({ $0.actor = actor; $0.id = id }, op: "claim")
    }

    /// Gives a claim back. `holder` guards against releasing a claim someone else took since.
    public func release(_ id: String, heldBy holder: String? = nil, force: Bool = false, as actor: String) throws(BeadsError) {
        _ = try send({ $0.actor = actor; $0.id = id; $0.expectedAssignee = holder; $0.force = force }, op: "release")
    }

    /// `id` depends on `target` with the given kind (default: target blocks id).
    public func link(_ id: String, dependsOn target: String, kind: LinkKind = .blocks, as actor: String) throws(BeadsError) {
        _ = try send({ $0.actor = actor; $0.id = id; $0.target = target; $0.linkType = kind.rawValue }, op: "link")
    }

    public func unlink(_ id: String, from target: String, as actor: String) throws(BeadsError) {
        _ = try send({ $0.actor = actor; $0.id = id; $0.target = target }, op: "unlink")
    }

    public func comment(on id: String, _ text: String, as actor: String) throws(BeadsError) {
        _ = try send({ $0.actor = actor; $0.id = id; $0.text = text }, op: "comment")
    }

    /// Resolves the gate (bd gate resolve): the work it holds becomes ready.
    public func approve(gate id: String, reason: String? = nil, as actor: String) throws(BeadsError) {
        _ = try send({ $0.actor = actor; $0.id = id; $0.reason = reason }, op: "approve_gate")
    }

    /// beads has no reject: the gate stays shut and the reason is left on it as a comment.
    public func reject(gate id: String, reason: String? = nil, as actor: String) throws(BeadsError) {
        _ = try send({ $0.actor = actor; $0.id = id; $0.reason = reason }, op: "reject_gate")
    }

    public func remember(_ text: String, key: String? = nil, as actor: String) throws(BeadsError) {
        _ = try send({ $0.actor = actor; $0.key = key; $0.text = text }, op: "remember")
    }

    public func forget(_ key: String, as actor: String) throws(BeadsError) {
        _ = try send({ $0.actor = actor; $0.key = key }, op: "forget")
    }
}
