import Foundation
import Testing
@testable import BeadsKit

private let root = URL(fileURLWithPath: "/Users/x/Developer/wander")
private let opened = #"{"handle":1,"project":{"beads_dir":"/Users/x/Developer/wander/.beads","database":"wa","mode":"embedded"}}"#

private func event(_ id: String, _ kind: String = "created", at: String = "2026-10-07T10:00:0") -> String {
    #"{"id":"\#(id)","issue_id":"wa-\#(id)","event_type":"\#(kind)","actor":"claude-1","created_at":"\#(at)\#(id.suffix(1))Z"}"#
}

private func page(_ ids: [String], more: Bool = false) -> String {
    let next = ids.last.map { #","next":{"at":"2026-10-07T10:00:0\#($0.suffix(1))Z","id":"\#($0)"}"# } ?? ""
    return #"{"events":[\#(ids.map { event($0) }.joined(separator: ","))]\#(next),"has_more":\#(more)}"#
}

@Test func changeSignalYieldsOnlyNewEventsInOrder() async throws {
    let engine = FakeEngine(["open": [opened], "events": [page(["1", "2"]), page([]), page(["3"])]])
    let ws = try Workspace(grantedFolder: CountingAccess(root), relativePath: ".beads", engine: engine)
    _ = try await ws.open()
    let feed = LiveFeed(workspace: ws, after: nil)
    var it = feed.updates.makeAsyncIterator()

    await feed.changed()
    #expect(try #require(await it.next()).map(\.id) == ["1", "2"])
    #expect(await feed.position == EventCursor(at: try Date("2026-10-07T10:00:02Z", strategy: .iso8601), id: "2"))

    await feed.changed() // nothing new: no yield
    await feed.changed()
    #expect(try #require(await it.next()).map(\.id) == ["3"])
    let sent = engine.seen.withLock { $0.filter { $0["op"] == "events" } }
    #expect(sent.count == 3)
    #expect(sent[0]["after"] == nil) // the first read starts at the beginning
}

@Test func morePagesAreReadInOneSignal() async throws {
    let engine = FakeEngine(["open": [opened], "events": [page(["1"], more: true), page(["2"], more: true), page(["3"])]])
    let ws = try Workspace(grantedFolder: CountingAccess(root), relativePath: ".beads", engine: engine)
    _ = try await ws.open()
    let feed = LiveFeed(workspace: ws, after: nil)
    var it = feed.updates.makeAsyncIterator()
    await feed.changed()
    #expect(try #require(await it.next()).map(\.id) == ["1", "2", "3"])
}

@Test func startAtNowSkipsHistory() async throws {
    let engine = FakeEngine(["open": [opened], "events": [page(["1", "2"]), page(["3"])]])
    let ws = try Workspace(grantedFolder: CountingAccess(root), relativePath: ".beads", engine: engine)
    _ = try await ws.open()
    let feed = LiveFeed(workspace: ws, after: nil)
    try await feed.startAtNow()
    var it = feed.updates.makeAsyncIterator()
    await feed.changed()
    #expect(try #require(await it.next()).map(\.id) == ["3"])
}

@Test func busyProjectYieldsNothingAndKeepsTheCursor() async throws {
    let engine = FakeEngine(["open": [opened], "events": [#"{"error":{"code":"busy","message":"exclusive lock"}}"#]])
    let ws = try Workspace(grantedFolder: CountingAccess(root), relativePath: ".beads", engine: engine)
    _ = try await ws.open()
    let start = EventCursor(at: Date(timeIntervalSince1970: 0), id: "0")
    let feed = LiveFeed(workspace: ws, after: start)
    await feed.changed()
    #expect(await feed.position == start)
}

@Test func cursorRoundTripsAsBeadsReadsIt() throws {
    let c = EventCursor(at: try Date("2026-10-07T10:00:02Z", strategy: .iso8601), id: "e1")
    let json = String(decoding: try JSONEncoder().encode(c), as: UTF8.self)
    #expect(json.contains("2026-10-07T10:00:02"))
    #expect(try BeadsJSON.decoder().decode(EventCursor.self, from: Data(json.utf8)) == c)
}

@Test func eventSummariesReadAsWords() throws {
    func e(_ kind: String, old: String? = nil, new: String? = nil) throws -> AuditEvent {
        var obj: [String: Any] = ["id": "1", "issue_id": "wa-1", "event_type": kind, "actor": "claude-1", "created_at": "2026-10-07T10:00:00Z"]
        if let old { obj["old_value"] = old }
        if let new { obj["new_value"] = new }
        return try BeadsJSON.decoder().decode(AuditEvent.self, from: JSONSerialization.data(withJSONObject: obj))
    }
    #expect(try e("created").summary == "claude-1 created it")
    #expect(try e("status_changed", old: "open", new: "in_progress").summary == "claude-1 set in progress")
    #expect(try e("dependency_added", new: "wa-91aa").summary == "claude-1 added a link to wa-91aa")
    #expect(try e("dependency_added", new: "Added dependency: a parent-child b").summary == "claude-1 added a link")
    #expect(try e("label_added").summary == "claude-1 added a label")
    #expect(try e("label_added", new: "sync").summary == "claude-1 added the label sync")
    #expect(try e("something_new").summary == "claude-1 something new")
}

@Test func runsOfTheSameChangeCollapse() throws {
    func item(_ id: String, _ kind: String, _ at: String, actor: String = "fixture", project: String = "many") throws -> ActivityItem {
        let obj: [String: Any] = ["id": id, "issue_id": "b-\(id)", "event_type": kind, "actor": actor, "created_at": at]
        let e = try BeadsJSON.decoder().decode(AuditEvent.self, from: JSONSerialization.data(withJSONObject: obj))
        return ActivityItem(projectID: project, project: project, event: e, title: nil)
    }
    let rows = ActivityItem.grouped([
        try item("1", "closed", "2026-10-07T12:00:00Z", actor: "claude-1"),
        try item("2", "created", "2026-10-07T11:00:50Z"),
        try item("3", "created", "2026-10-07T11:00:20Z"),
        try item("4", "created", "2026-10-07T10:59:40Z"),
        try item("5", "created", "2026-10-07T09:00:00Z"),
        try item("6", "created", "2026-10-07T08:59:59Z", project: "links"),
    ])
    #expect(rows.map(\.count) == [1, 3, 1, 1])
    #expect(rows[1].summary == "fixture created 3 beads")
    #expect(rows[0].summary == "claude-1 closed it")
}
