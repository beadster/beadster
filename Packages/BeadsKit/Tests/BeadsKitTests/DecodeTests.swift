import Foundation
import Testing
@testable import BeadsKit

// Every fixture here is bd 1.3.1's own --json output (macos/BeadsFFI/fixtures.sh).
private func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil))
    return try Data(contentsOf: url)
}

private func beads(_ name: String) throws -> [Bead] {
    try BeadsJSON.decoder().decode([Bead].self, from: fixture(name))
}

@Test func listDecodesEveryBead() throws {
    let list = try beads("links-list.json")
    #expect(list.count == 5)
    #expect(Set(list.map(\.type)) == [.epic, .bug, .task])
    let closed = try #require(list.first { $0.status == .closed })
    #expect(closed.title == "Merge by block id")
    #expect(closed.closedAt != nil)
    // list writes edges, not linked beads
    let banner = try #require(list.first { $0.title == "Conflict banner copy" })
    #expect(banner.dependencies.isEmpty)
    #expect(Set(banner.edges.map(\.kind)) == [.blocks, .parentChild])
}

@Test func showCarriesLinksLabelsAndComments() throws {
    let bead = try #require(try beads("links-show-paragraph.json").first)
    #expect(bead.type == .bug)
    #expect(bead.priority == 0)
    #expect(bead.labels == ["data-loss", "sync"])
    #expect(bead.comments.count == 1)
    #expect(bead.comments.first?.text == "Repro: two devices, offline edits.")
    #expect(bead.comments.first?.author == "fixture")
    #expect(bead.parentLink?.title == "Sync 2.0")
    #expect(bead.parentLink?.type == .epic)
    // "Conflict banner copy" is blocked by this bead; "Found while fixing" was discovered from it
    #expect(bead.holdsUp.map(\.title) == ["Conflict banner copy"])
    #expect(bead.dependents.contains { $0.kind == .discoveredFrom })
    #expect(bead.revision != nil)
}

@Test func relatesToIsNotBlocking() throws {
    let bead = try #require(try beads("links-show-closed.json").first)
    #expect(bead.closeReason == "done")
    #expect(bead.dependencies.map(\.kind) == [.relatesTo])
    #expect(bead.blockers.isEmpty)
    #expect(!LinkKind.relatesTo.isBlocking)
    #expect(LinkKind.blocks.isBlocking)
}

@Test func epicListsItsChildren() throws {
    let epic = try #require(try beads("links-show-epic.json").first)
    #expect(epic.type == .epic)
    #expect(epic.dependents.filter { $0.kind == .parentChild }.count == 2)
}

@Test func claimBecomesALease() throws {
    let bead = try #require(try beads("claims-show.json").first)
    #expect(bead.status == .inProgress)
    let lease = try #require(bead.lease)
    #expect(lease.holder == "claude-1")
    #expect(lease.expiresAt.timeIntervalSince(try #require(lease.heartbeatAt)) == 300)
    #expect(!lease.isExpired(at: lease.expiresAt.addingTimeInterval(-1)))
    #expect(lease.isExpired(at: lease.expiresAt))
    #expect(lease.silence(at: try #require(lease.heartbeatAt).addingTimeInterval(240)) == 240)
}

@Test func workflowStepsDecode() throws {
    let list = try beads("workflow-list.json")
    #expect(list.count == 5)
    #expect(list.contains { $0.title.contains("Run tests") })
}

@Test func gateCarriesItsCondition() throws {
    let lines = try #require(String(data: try fixture("gates-export.jsonl"), encoding: .utf8))
        .split(separator: "\n")
    var gates: [Bead] = []
    for line in lines {
        var object = try #require(try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        let bead = try BeadsJSON.decoder().decode(Bead.self, from: JSONSerialization.data(withJSONObject: object))
        if bead.type == .gate { gates.append(bead) }
    }
    #expect(Set(gates.compactMap(\.awaitType)) == ["human", "timer"])
}

@Test func memoriesAreKeyAndText() throws {
    let memories = try Memory.decodeList(fixture("memories.json"))
    #expect(memories.map(\.key) == ["deploy-rule", "vault-history"])
    #expect(memories.first?.text == "Never run wrangler deploy; use npm run deploy.")
}

@Test func unknownValuesSurviveRoundTrip() throws {
    #expect(BeadStatus(rawValue: "review") == .other("review"))
    #expect(BeadStatus(rawValue: "in_progress") == .inProgress)
    #expect(BeadStatus.inProgress.rawValue == "in_progress")
    #expect(BeadType(rawValue: "incident").rawValue == "incident")
    #expect(BeadType.milestone.rawValue == "milestone")
    #expect(LinkKind(rawValue: "parent-child") == .parentChild)
    #expect(LinkKind(rawValue: "tracks") == .other("tracks"))
    let encoded = try JSONEncoder().encode([BeadStatus.other("review"), .closed])
    #expect(String(data: encoded, encoding: .utf8) == #"["review","closed"]"#)
}

@Test func projectNameIsTheRepoFolder() {
    let p = Project(beadsDir: URL(fileURLWithPath: "/Users/x/Developer/wander/.beads"))
    #expect(p.name == "wander")
}
