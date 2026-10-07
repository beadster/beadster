import Foundation
import Testing
@testable import BeadsKit

private func bead(_ id: String, blockedBy: [String] = [], type: String = "task") throws -> Bead {
    let deps = blockedBy.map { ["issue_id": id, "depends_on_id": $0, "type": "blocks"] }
    let obj: [String: Any] = ["id": id, "title": id, "status": "open", "priority": 2, "issue_type": type,
                              "created_at": "2026-10-07T10:00:00Z", "updated_at": "2026-10-07T10:00:00Z",
                              "dependencies": deps]
    return try BeadsJSON.decoder().decode(Bead.self, from: JSONSerialization.data(withJSONObject: obj))
}

@Test func stepsSitBelowWhatTheyWaitOn() throws {
    // quick-check: lint, test, build, then report waits on all three
    let root = try bead("mol", type: "molecule")
    let map = DependencyMap(root: root, steps: [
        try bead("lint"), try bead("test"), try bead("build"), try bead("report", blockedBy: ["lint", "test", "build"]),
    ])
    let layer = Dictionary(uniqueKeysWithValues: map.nodes.map { ($0.id, $0.layer) })
    #expect(layer == ["mol": 0, "lint": 1, "test": 1, "build": 1, "report": 2])
    #expect(map.layers == 3)
    #expect(map.width(of: 1) == 3)
    #expect(Set(map.edges.filter { $0.from == "mol" }.map(\.to)) == ["lint", "test", "build"])
    #expect(map.edges.filter { $0.to == "report" }.count == 3)
}

@Test func chainsGoDeepAndBlockersOutsideAreIgnored() throws {
    let map = DependencyMap(root: try bead("e", type: "epic"), steps: [
        try bead("a"), try bead("b", blockedBy: ["a"]), try bead("c", blockedBy: ["b", "elsewhere"]),
    ])
    #expect(map.nodes.first { $0.id == "c" }?.layer == 3)
    #expect(!map.edges.contains { $0.from == "elsewhere" })
}

@Test func aCycleStillLaysOut() throws {
    let map = DependencyMap(root: try bead("e", type: "epic"), steps: [
        try bead("a", blockedBy: ["b"]), try bead("b", blockedBy: ["a"]),
    ])
    #expect(map.nodes.count == 3)
}

@Test func aStepWaitsOnItsOpenBlockers() throws {
    let steps = [try bead("lint"), try bead("test"), try bead("report", blockedBy: ["lint", "test"])]
    let flow = Workflow(root: try bead("mol", type: "molecule"), steps: steps)
    #expect(flow.openBlockers(of: steps[2]).map(\.id) == ["lint", "test"])
    #expect(flow.openBlockers(of: steps[0]).isEmpty)
}
