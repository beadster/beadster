import Foundation
import Testing
@testable import BeadsKit

private func version(_ commit: String, _ at: String, title: String, status: String = "open", priority: Int = 2) throws -> HistoryEntry {
    let obj: [String: Any] = ["commit": commit, "committer": "claude-2", "date": at,
                              "issue": ["id": "td-1", "title": title, "status": status, "priority": priority, "issue_type": "task",
                                        "created_at": "2026-10-07T09:00:00Z", "updated_at": at]]
    return try BeadsJSON.decoder().decode(HistoryEntry.self, from: JSONSerialization.data(withJSONObject: obj))
}

@Test func changesAreFieldByFieldNewestFirst() throws {
    let entries = [
        try version("c3", "2026-10-07T11:00:00Z", title: "Billing page: next invoice", status: "in_progress", priority: 1),
        try version("c1", "2026-10-07T09:00:00Z", title: "Billing page tweaks"),
        try version("c2", "2026-10-07T10:00:00Z", title: "Billing page tweaks", status: "in_progress"),
    ]
    let changes = BeadHistory.changes(entries)
    #expect(changes.map(\.field) == ["title", "priority", "status"])
    #expect(changes[0].before == "Billing page tweaks")
    #expect(changes[2].after == "in progress")
    #expect(changes.allSatisfy { $0.who == "claude-2" })
}

@Test func whoComesFromTheAuditLogBesideTheCommit() throws {
    let entries = [try version("c1", "2026-10-07T09:00:00Z", title: "a"), try version("c2", "2026-10-07T10:00:00Z", title: "b")]
    let obj: [String: Any] = ["id": "e", "issue_id": "td-1", "event_type": "updated", "actor": "anton", "created_at": "2026-10-07T10:00:01Z"]
    let event = try BeadsJSON.decoder().decode(AuditEvent.self, from: JSONSerialization.data(withJSONObject: obj))
    #expect(BeadHistory.changes(entries, events: [event]).first?.who == "anton")
    #expect(BeadHistory.changes(entries).first?.who == "claude-2") // no event: the committer
}
