import Foundation
import Testing
@testable import BeadsKit

private func bead(_ id: String, title: String, extra: [String: Any] = [:]) throws -> Bead {
    var obj: [String: Any] = ["id": id, "title": title, "status": "open", "priority": 1, "issue_type": "task",
                              "created_at": "2026-10-07T10:00:00Z", "updated_at": "2026-10-07T10:00:00Z"]
    obj.merge(extra) { $1 }
    return try BeadsJSON.decoder().decode(Bead.self, from: JSONSerialization.data(withJSONObject: obj))
}

@Test func firstLookIsTheBaselineThenOnlyWhatIsNew() throws {
    var state = NoticeState()
    let now = try Date("2026-10-07T12:00:00Z", strategy: .iso8601)
    let gate1 = Gate(bead: try bead("g1", title: "Gate: human", extra: ["issue_type": "gate", "await_type": "human",
                                                                       "description": "x\n\nReason: Approve the deploy"]),
                     holds: [LinkedBead(id: "w1", title: "Deploy to production", status: .open, priority: 1, type: .task, kind: .blocks)])
    var needs = ProjectLibrary.NeedsYou()
    needs.approvals = [("p", "tinydot", gate1)]
    #expect(state.update(needsYou: needs, working: [], closedEvents: [], now: now).isEmpty) // baseline

    let gate2 = Gate(bead: try bead("g2", title: "Gate: human", extra: ["issue_type": "gate", "await_type": "human"]), holds: [])
    needs.approvals.append(("p", "tinydot", gate2))
    needs.assigned = [("p", "tinydot", try bead("a1", title: "Pick the words"))]
    let quietBead = try bead("q1", title: "Billing page", extra: ["assignee": "claude-2", "status": "in_progress",
                                                                   "heartbeat_at": "2026-10-07T11:55:00Z",
                                                                   "lease_expires_at": "2026-10-07T12:01:00Z"])
    let notices = state.update(needsYou: needs, working: [("p", "tinydot", quietBead)], closedEvents: [], now: now)
    #expect(notices.map(\.kind) == [.assigned, .gate, .quiet])
    #expect(notices.first { $0.kind == .quiet }?.title == "claude-2 has gone quiet")
    #expect(notices.first { $0.kind == .gate }?.beadID == "g2")

    // nothing new: silent
    #expect(state.update(needsYou: needs, working: [("p", "tinydot", quietBead)], closedEvents: [], now: now).isEmpty)
}
