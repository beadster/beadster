import Foundation
import Testing
@testable import BeadsKit

private func gateBead(_ awaitType: String, description: String?) throws -> Bead {
    var obj: [String: Any] = ["id": "gt-1", "title": "Gate: \(awaitType)", "status": "open", "priority": 2,
                              "issue_type": "gate", "await_type": awaitType,
                              "created_at": "2026-10-07T10:00:00Z", "updated_at": "2026-10-07T10:00:00Z"]
    if let description { obj["description"] = description }
    return try BeadsJSON.decoder().decode(Bead.self, from: JSONSerialization.data(withJSONObject: obj))
}

private let held = LinkedBead(id: "gt-7t2", title: "Deploy to production", status: .open, priority: 1, type: .task, kind: .blocks)

@Test func humanGateReadsAsTheWorkItHolds() throws {
    let g = Gate(bead: try gateBead("human", description: "Ad-hoc gate blocking gt-7t2\n\nReason: Approve the deploy"), holds: [held])
    #expect(g.needsAPerson)
    #expect(g.title == "Deploy to production")
    #expect(g.reason == "Approve the deploy")
}

@Test func otherConditionsWaitWithoutAPerson() throws {
    let timer = Gate(bead: try gateBead("timer", description: "Ad-hoc gate blocking gt-cxy"), holds: [])
    #expect(!timer.needsAPerson)
    #expect(timer.reason == nil)
    #expect(timer.title == "Gate: timer")
    #expect(Gate(bead: try gateBead("gh:pr", description: nil), holds: []).condition == .pullRequest(nil))
}
