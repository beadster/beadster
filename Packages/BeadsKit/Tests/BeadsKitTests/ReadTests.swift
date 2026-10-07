import Foundation
import Testing
@testable import BeadsKit

private let root = URL(fileURLWithPath: "/Users/x/Developer/wander")
private let opened = #"{"handle":7,"project":{"beads_dir":"/Users/x/Developer/wander/.beads","database":"wa","mode":"embedded"}}"#

private func openWorkspace(_ answers: [String: [String]]) async throws -> (Workspace, FakeEngine) {
    var all = answers
    all["open"] = [opened]
    let engine = FakeEngine(all)
    let ws = try Workspace(grantedFolder: CountingAccess(root), relativePath: ".beads", engine: engine)
    #expect(try await ws.open() == .ready)
    return (ws, engine)
}

private func fixtureText(_ name: String) throws -> String {
    let url = try #require(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil))
    return try String(contentsOf: url, encoding: .utf8)
}

@Test func listSendsFiltersAndDecodesBdsOwnRows() async throws {
    let rows = try fixtureText("links-list.json")
    let (ws, engine) = try await openWorkspace(["list": [#"{"issues":\#(rows),"has_more":false}"#]])
    let page = try await ws.list(BeadFilter(status: .open, type: .bug, label: "sync", titleContains: "para", limit: 50))
    #expect(page.beads.count == 5)
    let sent = try #require(engine.seen.withLock { $0.last })
    #expect(sent["handle"] == "7")
    #expect(sent["status"] == "open")
    #expect(sent["filter_type"] == "bug")
    #expect(sent["label"] == "sync")
    #expect(sent["title_contains"] == "para")
    #expect(sent["limit"] == "50")
}

@Test func showReturnsTheBeadWithItsLinks() async throws {
    let detail = try fixtureText("links-show-paragraph.json").trimmingCharacters(in: .whitespacesAndNewlines)
    let single = String(detail.dropFirst().dropLast()) // bd show prints an array of one
    let (ws, _) = try await openWorkspace(["show": [#"{"details":\#(single)}"#]])
    let bead = try await ws.show("ln-tvl")
    #expect(bead.comments.count == 1)
    #expect(bead.parentLink?.title == "Sync 2.0")
}

@Test func blockedCarriesWhatHoldsIt() async throws {
    let (ws, _) = try await openWorkspace(["blocked": [#"""
    {"blocked":[{"id":"wa-91aa","title":"Conflict banner copy","status":"open","priority":2,"issue_type":"task",
    "created_at":"2026-10-07T10:00:00Z","updated_at":"2026-10-07T10:00:00Z","blocked_by_count":1,"blocked_by":["wa-7f3a"]}]}
    """#]])
    let blocked = try await ws.blocked()
    #expect(blocked.map(\.id) == ["wa-91aa"])
    #expect(blocked.first?.blockedBy == ["wa-7f3a"])
}

@Test func historyMemoriesAndProgressDecode() async throws {
    let (ws, _) = try await openWorkspace([
        "history": [#"""
        {"history":[{"commit":"8q1v2c0","committer":"claude-2","date":"2026-10-07T10:41:00Z",
        "issue":{"id":"td-0b19","title":"Billing page","status":"in_progress","priority":2,"issue_type":"task",
        "created_at":"2026-10-06T10:00:00Z","updated_at":"2026-10-07T10:41:00Z"}}]}
        """#],
        "memories": [#"{"memories":{"vault-history":"History lives in .wander.","deploy":"npm run deploy"}}"#],
        "molecule_progress": [#"{"progress":{"molecule_id":"wf-mol-nrb","molecule_title":"quick-check","total":4,"completed":1,"in_progress":1,"current_step_id":"wf-mol-1hx"}}"#],
    ])
    let history = try await ws.history("td-0b19")
    #expect(history.first?.committer == "claude-2")
    #expect(history.first?.bead?.status == .inProgress)
    #expect(try await ws.memories().map(\.key) == ["deploy", "vault-history"])
    let p = try await ws.progress(ofMolecule: "wf-mol-nrb")
    #expect(p.total == 4)
    #expect(p.fraction == 0.25)
    #expect(p.currentStepID == "wf-mol-1hx")
}

@Test func workingAsksForInProgress() async throws {
    let claim = try fixtureText("claims-show.json")
    let (ws, engine) = try await openWorkspace(["list": [#"{"issues":\#(claim)}"#]])
    let beads = try await ws.working()
    #expect(beads.first?.lease?.holder == "claude-1")
    #expect(engine.seen.withLock { $0.last?["status"] } == "in_progress")
}
