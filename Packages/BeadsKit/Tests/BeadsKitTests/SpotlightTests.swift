import Foundation
import Testing
@testable import BeadsKit

private func bead(_ id: String, _ status: String, labels: [String] = []) throws -> Bead {
    let obj: [String: Any] = ["id": id, "title": "Title \(id)", "status": status, "priority": 1, "issue_type": "task",
                              "labels": labels, "description": "about \(id)",
                              "created_at": "2026-10-07T10:00:00Z", "updated_at": "2026-10-07T11:00:00Z"]
    return try BeadsJSON.decoder().decode(Bead.self, from: JSONSerialization.data(withJSONObject: obj))
}

@Test func openBeadsAreFoundByTitleIdProjectAndLabelsAndOpenTheirBead() throws {
    let items = SpotlightItem.items(projectID: "folder.1/wander/.beads", project: "wander",
                                    beads: [try bead("wa-1", "open", labels: ["ui"]), try bead("wa-2", "closed"),
                                            try bead("wa-3", "in_progress")])
    #expect(items.map(\.uniqueID) == ["folder.1/wander/.beads|wa-1", "folder.1/wander/.beads|wa-3"])
    #expect(items[0].keywords == ["wa-1", "wander", "ui"])
    #expect(items[0].detail == "wa-1 · wander")
    #expect(items[0].domain == "folder.1/wander/.beads")
    let target = try #require(SpotlightItem.target(of: items[0].uniqueID))
    #expect(target.projectID == "folder.1/wander/.beads" && target.beadID == "wa-1")
    #expect(SpotlightItem.target(of: "no-bar") == nil)
    #expect(SpotlightItem.target(of: "p|") == nil)
}
