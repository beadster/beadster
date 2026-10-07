import Foundation

/// One bead as beads 1.3 writes it (types.Issue, plus the counts list and ready add).
public struct Bead: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public var title: String
    public var status: BeadStatus
    public var priority: Int
    public var type: BeadType
    public var description: String?
    public var design: String?
    public var acceptanceCriteria: String?
    public var notes: String?
    public var assignee: String?
    public var owner: String?
    public var createdBy: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var startedAt: Date?
    public var closedAt: Date?
    public var closeReason: String?
    public var dueAt: Date?
    public var deferUntil: Date?
    public var externalRef: String?
    public var estimatedMinutes: Int?
    public var labels: [String]
    public var parent: String?
    // claims (work leases)
    public var leaseExpiresAt: Date?
    public var heartbeatAt: Date?
    // gates
    public var awaitType: String?
    public var awaitID: String?
    // workflows
    public var molType: String?
    public var ephemeral: Bool
    // counts
    public var dependencyCount: Int
    public var dependentCount: Int
    public var commentCount: Int
    /// Edges as list and export write them (ids only). show writes `dependencies` instead.
    public var edges: [DependencyEdge]
    // show only
    public var dependencies: [LinkedBead]
    public var dependents: [LinkedBead]
    public var comments: [Comment]
    /// Opaque version token for compare-and-set writes.
    public var revision: String?

    enum CodingKeys: String, CodingKey {
        case id, title, status, priority, description, design, notes, assignee, owner, labels, parent
        case comments, dependencies, dependents, revision, ephemeral
        case type = "issue_type"
        case acceptanceCriteria = "acceptance_criteria"
        case createdBy = "created_by", createdAt = "created_at", updatedAt = "updated_at"
        case startedAt = "started_at", closedAt = "closed_at", closeReason = "close_reason"
        case dueAt = "due_at", deferUntil = "defer_until", externalRef = "external_ref"
        case estimatedMinutes = "estimated_minutes"
        case leaseExpiresAt = "lease_expires_at", heartbeatAt = "heartbeat_at"
        case awaitType = "await_type", awaitID = "await_id", molType = "mol_type"
        case dependencyCount = "dependency_count", dependentCount = "dependent_count", commentCount = "comment_count"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        status = try c.decodeIfPresent(BeadStatus.self, forKey: .status) ?? .open
        priority = try c.decodeIfPresent(Int.self, forKey: .priority) ?? 2
        type = try c.decodeIfPresent(BeadType.self, forKey: .type) ?? .task
        description = try c.decodeIfPresent(String.self, forKey: .description)
        design = try c.decodeIfPresent(String.self, forKey: .design)
        acceptanceCriteria = try c.decodeIfPresent(String.self, forKey: .acceptanceCriteria)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        assignee = try c.decodeIfPresent(String.self, forKey: .assignee)
        owner = try c.decodeIfPresent(String.self, forKey: .owner)
        createdBy = try c.decodeIfPresent(String.self, forKey: .createdBy)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt)
        closedAt = try c.decodeIfPresent(Date.self, forKey: .closedAt)
        closeReason = try c.decodeIfPresent(String.self, forKey: .closeReason)
        dueAt = try c.decodeIfPresent(Date.self, forKey: .dueAt)
        deferUntil = try c.decodeIfPresent(Date.self, forKey: .deferUntil)
        externalRef = try c.decodeIfPresent(String.self, forKey: .externalRef)
        estimatedMinutes = try c.decodeIfPresent(Int.self, forKey: .estimatedMinutes)
        labels = try c.decodeIfPresent([String].self, forKey: .labels) ?? []
        parent = try c.decodeIfPresent(String.self, forKey: .parent)
        leaseExpiresAt = try c.decodeIfPresent(Date.self, forKey: .leaseExpiresAt)
        heartbeatAt = try c.decodeIfPresent(Date.self, forKey: .heartbeatAt)
        awaitType = try c.decodeIfPresent(String.self, forKey: .awaitType)
        awaitID = try c.decodeIfPresent(String.self, forKey: .awaitID)
        molType = try c.decodeIfPresent(String.self, forKey: .molType)
        ephemeral = try c.decodeIfPresent(Bool.self, forKey: .ephemeral) ?? false
        dependencyCount = try c.decodeIfPresent(Int.self, forKey: .dependencyCount) ?? 0
        dependentCount = try c.decodeIfPresent(Int.self, forKey: .dependentCount) ?? 0
        commentCount = try c.decodeIfPresent(Int.self, forKey: .commentCount) ?? 0
        // the same key holds two shapes: linked beads (show) or edge rows (list, export)
        if let linked = try? c.decodeIfPresent([LinkedBead].self, forKey: .dependencies) {
            dependencies = linked
            let own = id
            edges = linked.map { DependencyEdge(issueID: own, dependsOnID: $0.id, kind: $0.kind) }
        } else {
            edges = try c.decodeIfPresent([DependencyEdge].self, forKey: .dependencies) ?? []
            dependencies = []
        }
        dependents = try c.decodeIfPresent([LinkedBead].self, forKey: .dependents) ?? []
        comments = try c.decodeIfPresent([Comment].self, forKey: .comments) ?? []
        revision = try c.decodeIfPresent(String.self, forKey: .revision)
    }

    /// The claim an agent holds on this bead, if any.
    public var lease: Lease? {
        guard let assignee, let leaseExpiresAt else { return nil }
        return Lease(beadID: id, holder: assignee, expiresAt: leaseExpiresAt, heartbeatAt: heartbeatAt ?? startedAt)
    }

    /// Beads this one waits on (its blocking dependencies).
    public var blockers: [LinkedBead] { dependencies.filter { $0.kind.isBlocking } }
    /// Beads waiting on this one.
    public var holdsUp: [LinkedBead] { dependents.filter { $0.kind.isBlocking } }
    /// The epic or molecule this bead belongs to.
    public var parentLink: LinkedBead? { dependencies.first { $0.kind == .parentChild } }
}

/// One dependency edge: `issueID` depends on `dependsOnID` (list and export rows).
public struct DependencyEdge: Hashable, Sendable, Codable {
    public let issueID: String
    public let dependsOnID: String
    public let kind: LinkKind

    enum CodingKeys: String, CodingKey {
        case issueID = "issue_id", dependsOnID = "depends_on_id", kind = "type"
    }
}

/// A bead on the other end of a dependency, with the kind of the edge.
public struct LinkedBead: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public var title: String
    public var status: BeadStatus
    public var priority: Int
    public var type: BeadType
    public var kind: LinkKind

    enum CodingKeys: String, CodingKey {
        case id, title, status, priority
        case type = "issue_type", kind = "dependency_type"
    }
}

public struct Comment: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public var author: String
    public var text: String
    public var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, author, text
        case createdAt = "created_at"
    }
}

/// A work claim: an agent holds the bead until `expiresAt`; heartbeats extend it.
public struct Lease: Hashable, Sendable {
    public let beadID: String
    public let holder: String
    public let expiresAt: Date
    public let heartbeatAt: Date?

    public func isExpired(at now: Date) -> Bool { expiresAt <= now }
    /// Seconds since the holder was last heard from.
    public func silence(at now: Date) -> TimeInterval? { heartbeatAt.map { now.timeIntervalSince($0) } }
}

/// A `bd remember` fact: a key and its text.
public struct Memory: Identifiable, Hashable, Sendable {
    public var id: String { key }
    public let key: String
    public let text: String

    /// `bd memories --json` is one object of key → text (plus schema_version).
    public static func decodeList(_ data: Data) throws -> [Memory] {
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        return object.compactMap { key, value in
            guard key != "schema_version", let text = value as? String else { return nil }
            return Memory(key: key, text: text)
        }
        .sorted { $0.key < $1.key }
    }
}

/// One committed change from the events journal (bd events / internal/eventsjournal.Record).
public struct JournalEvent: Identifiable, Hashable, Sendable, Codable {
    public var id: Int64 { seq }
    public let seq: Int64
    public let ts: String
    public let op: String
    public let issueID: String
    public let actor: String?

    enum CodingKeys: String, CodingKey {
        case seq, ts, op, actor
        case issueID = "issue_id"
    }
}

/// A project beadster can open: the folder that holds `.beads`.
public struct Project: Identifiable, Hashable, Sendable {
    public var id: String { beadsDir.path }
    public let name: String
    public let beadsDir: URL

    public init(beadsDir: URL) {
        self.beadsDir = beadsDir
        name = beadsDir.deletingLastPathComponent().lastPathComponent
    }
}

public enum BeadsJSON {
    /// beads writes RFC 3339 times, with or without fractional seconds.
    public static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            if let date = try? Date(s, strategy: .iso8601) { return date }
            if let date = try? Date(s, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "not RFC 3339: \(s)"))
        }
        return d
    }
}
