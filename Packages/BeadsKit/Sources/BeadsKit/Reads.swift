import Foundation

/// A bead held out of Ready, with the ids of the beads holding it.
public struct BlockedBead: Identifiable, Hashable, Sendable, Decodable {
    public var id: String { bead.id }
    public let bead: Bead
    public let blockedBy: [String]

    enum CodingKeys: String, CodingKey { case blockedBy = "blocked_by" }

    public init(from decoder: Decoder) throws {
        bead = try Bead(from: decoder)
        blockedBy = try decoder.container(keyedBy: CodingKeys.self).decodeIfPresent([String].self, forKey: .blockedBy) ?? []
    }
}

/// One Dolt commit that touched a bead: who, when, and the bead as it was then.
public struct HistoryEntry: Identifiable, Hashable, Sendable, Decodable {
    public var id: String { commit }
    public let commit: String
    public let committer: String
    public let date: Date
    public let bead: Bead?

    enum CodingKeys: String, CodingKey {
        case commit, committer, date
        case bead = "issue"
    }
}

/// How far a workflow (molecule) has come.
public struct MoleculeProgress: Hashable, Sendable, Decodable {
    public let moleculeID: String
    public let title: String
    public let total: Int
    public let completed: Int
    public let inProgress: Int
    public let currentStepID: String?

    public var fraction: Double { total == 0 ? 0 : Double(completed) / Double(total) }

    enum CodingKeys: String, CodingKey {
        case total, completed
        case moleculeID = "molecule_id", title = "molecule_title"
        case inProgress = "in_progress", currentStepID = "current_step_id"
    }
}

/// What a list asks for; nil leaves beads' own default.
public struct BeadFilter: Hashable, Sendable {
    public var status: BeadStatus?
    public var type: BeadType?
    public var assignee: String?
    public var label: String?
    public var titleContains: String?
    public var limit: Int?
    /// Closed beads too (bd list --all).
    public var includeClosed: Bool

    public init(status: BeadStatus? = nil, type: BeadType? = nil, assignee: String? = nil,
                label: String? = nil, titleContains: String? = nil, limit: Int? = nil, includeClosed: Bool = false) {
        self.includeClosed = includeClosed
        self.status = status
        self.type = type
        self.assignee = assignee
        self.label = label
        self.titleContains = titleContains
        self.limit = limit
    }
}

/// One page of beads and whether beads holds more.
public struct BeadPage: Sendable {
    public let beads: [Bead]
    public let hasMore: Bool
}

extension Workspace {
    /// Ready work in beads' own order (priority, then age).
    public func ready(limit: Int? = nil) throws(BeadsError) -> BeadPage {
        let r = try send({ $0.limit = limit }, op: "ready")
        return BeadPage(beads: r.issues ?? [], hasMore: r.hasMore ?? false)
    }

    public func list(_ filter: BeadFilter = BeadFilter()) throws(BeadsError) -> BeadPage {
        let r = try send({
            $0.status = filter.status?.rawValue
            $0.filterType = filter.type?.rawValue
            $0.filterAssignee = filter.assignee
            $0.label = filter.label
            $0.titleContains = filter.titleContains
            $0.limit = filter.limit
            $0.all = filter.includeClosed ? true : nil
        }, op: "list")
        return BeadPage(beads: r.issues ?? [], hasMore: r.hasMore ?? false)
    }

    /// One bead with its links, dependents and comments.
    public func show(_ id: String) throws(BeadsError) -> Bead {
        guard let bead = try send({ $0.id = id }, op: "show").details else { throw .notFound(id) }
        return bead
    }

    public func blocked() throws(BeadsError) -> [BlockedBead] {
        try send({ _ in }, op: "blocked").blocked ?? []
    }

    /// Every commit that touched the bead, newest first as beads returns it.
    public func history(_ id: String) throws(BeadsError) -> [HistoryEntry] {
        try send({ $0.id = id }, op: "history").history ?? []
    }

    public func memories() throws(BeadsError) -> [Memory] {
        (try send({ _ in }, op: "memories").memories ?? [:])
            .map { Memory(key: $0.key, text: $0.value) }
            .sorted { $0.key < $1.key }
    }

    public func progress(ofMolecule id: String) throws(BeadsError) -> MoleculeProgress {
        guard let p = try send({ $0.id = id }, op: "molecule_progress").progress else { throw .notFound(id) }
        return p
    }

    /// Beads an agent (or person) is working on right now, with their claims.
    public func working() throws(BeadsError) -> [Bead] {
        try list(BeadFilter(status: .inProgress)).beads
    }
}
