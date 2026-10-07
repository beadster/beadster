import Foundation
import Testing
@testable import BeadsKit

private let root = URL(fileURLWithPath: "/Users/x/Developer/wander")
private let opened = #"{"handle":3,"project":{"beads_dir":"/Users/x/Developer/wander/.beads","database":"wa","mode":"embedded"}}"#
private let bead = #"{"id":"wa-1","title":"T","status":"open","priority":2,"issue_type":"task","created_at":"2026-10-07T10:00:00Z","updated_at":"2026-10-07T10:00:00Z"}"#

private func workspace(_ answers: [String: [String]]) async throws -> (Workspace, FakeEngine) {
    var all = answers
    all["open"] = [opened]
    let engine = FakeEngine(all)
    let ws = try Workspace(grantedFolder: CountingAccess(root), relativePath: ".beads", engine: engine)
    _ = try await ws.open()
    return (ws, engine)
}

@Test func createSendsTheNewBead() async throws {
    let (ws, engine) = try await workspace(["create": [#"{"issue":\#(bead),"changed":true}"#]])
    let made = try await ws.create(NewBead(title: "T", type: .bug, priority: 0, parent: "wa-e210"), as: "anton")
    #expect(made.id == "wa-1")
    let sent = try #require(engine.seen.withLock { $0.last })
    #expect(sent["actor"] == "anton")
    #expect(sent["issue_type"] == "bug")
    #expect(sent["priority"] == "0")
    #expect(sent["parent"] == "wa-e210")
}

@Test func updateSendsOnlyWhatChangesAndTheGuards() async throws {
    let (ws, engine) = try await workspace(["update": [#"{"issue":\#(bead),"changed":true}"#]])
    var edit = BeadEdit()
    edit.status = .inProgress
    edit.addLabels = ["sync"]
    edit.ifStatus = .open
    edit.ifAssignee = ""
    try await ws.update("wa-1", edit, as: "anton")
    let sent = try #require(engine.seen.withLock { $0.last })
    #expect(sent["new_status"] == "in_progress")
    #expect(sent["expected_status"] == "open")
    #expect(sent["expected_assignee"] == "")
    #expect(sent["title"] == nil)
    #expect(sent["priority"] == nil)
}

@Test func refusalsAreTyped() async throws {
    let (ws, _) = try await workspace([
        "update": [#"{"error":{"code":"conflict","message":"status mismatch"}}"#],
        "claim": [#"{"error":{"code":"claimed","message":"issue claimed by a different actor"}}"#],
        "link": [#"{"error":{"code":"refused","message":"adding dependency would create a cycle"}}"#],
    ])
    await #expect(throws: BeadsError.conflict("status mismatch")) { try await ws.update("wa-1", BeadEdit(), as: "a") }
    await #expect(throws: BeadsError.claimed("issue claimed by a different actor")) { try await ws.claim("wa-1", as: "a") }
    await #expect(throws: BeadsError.refused("adding dependency would create a cycle")) {
        try await ws.link("wa-1", dependsOn: "wa-2", as: "a")
    }
}

@Test func everyWriteNamesItsOp() async throws {
    let ops = ["close_issue", "reopen", "claim", "release", "link", "unlink", "comment",
               "approve_gate", "reject_gate", "remember", "forget"]
    var answers: [String: [String]] = [:]
    for op in ops { answers[op] = [#"{"changed":true}"#] }
    let (ws, engine) = try await workspace(answers)
    try await ws.close("wa-1", reason: "done", as: "a")
    try await ws.reopen("wa-1", as: "a")
    try await ws.claim("wa-1", as: "a")
    try await ws.release("wa-1", heldBy: "a", as: "a")
    try await ws.link("wa-2", dependsOn: "wa-1", kind: .relatesTo, as: "a")
    try await ws.unlink("wa-2", from: "wa-1", as: "a")
    try await ws.comment(on: "wa-1", "hi", as: "a")
    try await ws.approve(gate: "wa-g1", as: "a")
    try await ws.reject(gate: "wa-g1", reason: "not today", as: "a")
    try await ws.remember("npm run deploy", key: "deploy", as: "a")
    try await ws.forget("deploy", as: "a")
    #expect(Array(engine.ops.dropFirst()) == ops)
    let link = try #require(engine.seen.withLock { $0.first { $0["op"] == "link" } })
    #expect(link["link_type"] == "relates-to")
    #expect(link["target"] == "wa-1")
}
