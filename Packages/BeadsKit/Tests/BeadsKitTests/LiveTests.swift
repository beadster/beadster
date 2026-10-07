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
