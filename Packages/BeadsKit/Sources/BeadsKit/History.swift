import Foundation

/// One field that changed between two Dolt versions of a bead.
public struct FieldChange: Identifiable, Hashable, Sendable {
    public var id: String { "\(commit)|\(field)" }
    public let commit: String
    public let at: Date
    public let who: String
    public let field: String
    public let before: String
    public let after: String
}

public enum BeadHistory {
    /// The fields a person reads, in the order the table shows them.
    static let fields: [(String, @Sendable (Bead) -> String)] = [
        ("title", { $0.title }),
        ("status", { $0.status.rawValue.replacingOccurrences(of: "_", with: " ") }),
        ("priority", { "P\($0.priority)" }),
        ("type", { $0.type.rawValue }),
        ("assignee", { $0.assignee ?? "" }),
        ("description", { $0.description ?? "" }),
        ("design", { $0.design ?? "" }),
        ("acceptance", { $0.acceptanceCriteria ?? "" }),
        ("notes", { $0.notes ?? "" }),
    ]

    /// Every field change across the versions, newest first. The first version is the bead as
    /// created and has nothing before it.
    public static func changes(_ entries: [HistoryEntry], events: [AuditEvent] = []) -> [FieldChange] {
        let versions = entries.filter { $0.bead != nil }.sorted { $0.date < $1.date }
        // Dolt's committer is beads' own name; who made the change is in the audit log, written
        // in the same moment as the commit
        func who(_ e: HistoryEntry) -> String {
            let near = events.min { abs($0.at.timeIntervalSince(e.date)) < abs($1.at.timeIntervalSince(e.date)) }
            if let near, abs(near.at.timeIntervalSince(e.date)) <= 5 { return near.actor }
            return e.committer
        }
        var out: [FieldChange] = []
        for (prev, next) in zip(versions, versions.dropFirst()) {
            guard let a = prev.bead, let b = next.bead else { continue }
            for (name, read) in fields where read(a) != read(b) {
                out.append(FieldChange(commit: next.commit, at: next.date, who: who(next),
                                       field: name, before: read(a), after: read(b)))
            }
        }
        return out.sorted { $0.at > $1.at }
    }
}

extension Workspace {
    /// Writes an earlier version's fields back as a new change, through beads, as `actor`.
    /// History is never rewritten: the restore is one more version on top.
    public func restore(_ id: String, to version: Bead, as actor: String) throws(BeadsError) {
        var edit = BeadEdit()
        edit.title = version.title
        edit.description = version.description ?? ""
        edit.design = version.design ?? ""
        edit.acceptanceCriteria = version.acceptanceCriteria ?? ""
        edit.notes = version.notes ?? ""
        edit.status = version.status
        edit.priority = version.priority
        edit.type = version.type
        edit.assignee = version.assignee ?? ""
        try update(id, edit, as: actor)
    }
}
