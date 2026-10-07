import Foundation
import Synchronization
import Testing
@testable import BeadsKit

/// Answers with canned JSON per op and records every request.
final class FakeEngine: BeadsEngine {
    let answers: Mutex<[String: [String]]>
    let seen = Mutex<[[String: String]]>([])
    init(_ answers: [String: [String]]) { self.answers = Mutex(answers) }

    func call(_ request: Data) -> Data {
        let object = (try? JSONSerialization.jsonObject(with: request) as? [String: Any]) ?? [:]
        let flat = object.mapValues { "\($0)" }
        seen.withLock { $0.append(flat) }
        let op = object["op"] as? String ?? ""
        let out = answers.withLock { a -> String in
            guard var list = a[op], !list.isEmpty else { return #"{"error":{"code":"bad_request","message":"no answer for \#(op)"}}"# }
            let first = list.removeFirst()
            a[op] = list.isEmpty ? [first] : list
            return first
        }
        return Data(out.utf8)
    }

    var ops: [String] { seen.withLock { $0.compactMap { $0["op"] } } }
}

final class CountingAccess: FolderAccess {
    let url: URL?
    let counts = Mutex((start: 0, stop: 0))
    init(_ url: URL?) { self.url = url }
    func start() -> URL? { counts.withLock { $0.start += 1 }; return url }
    func stop() { counts.withLock { $0.stop += 1 } }
}

private let root = URL(fileURLWithPath: "/Users/x/Developer/wander")
private let ok = #"{"handle":1,"project":{"beads_dir":"/Users/x/Developer/wander/.beads","database":"wa","mode":"embedded"}}"#

@Test func opensReadyAndSendsTheBeadsFolder() async throws {
    let engine = FakeEngine(["open": [ok], "close": ["{}"]])
    let access = CountingAccess(root)
    let ws = try Workspace(grantedFolder: access, relativePath: ".beads", engine: engine)
    #expect(ws.project.name == "wander")
    #expect(try await ws.open() == .ready)
    #expect(engine.seen.withLock { $0.first?["beads_dir"] } == "/Users/x/Developer/wander/.beads")
    await ws.close()
    #expect(engine.ops == ["open", "close"])
    // init checks the grant once, open holds access, close releases it
    #expect(access.counts.withLock { $0.start } == 2)
    #expect(access.counts.withLock { $0.stop } == 2)
}

@Test func olderSchemaAsksAndMigratesOnlyWhenTold() async throws {
    let behind = #"{"error":{"code":"schema_behind","message":"schema version mismatch: database is at v60","db_version":60,"binary_version":65}}"#
    let engine = FakeEngine(["open": [behind, ok], "migrate": [#"{"changed":true}"#]])
    let ws = try Workspace(grantedFolder: CountingAccess(root), relativePath: ".beads", engine: engine)
    #expect(try await ws.open() == .needsMigration(dbVersion: 60, appVersion: 65))
    #expect(!engine.ops.contains("migrate"))
    #expect(try await ws.migrate() == .ready)
    #expect(engine.ops == ["open", "migrate", "open"])
}

@Test func newerSchemaReadsNothing() async throws {
    let ahead = #"{"error":{"code":"schema_ahead","message":"database is 2 migrations ahead","db_version":67,"binary_version":65}}"#
    let engine = FakeEngine(["open": [ahead]])
    let ws = try Workspace(grantedFolder: CountingAccess(root), relativePath: ".beads", engine: engine)
    #expect(try await ws.open() == .needsNewerApp(dbVersion: 67, appVersion: 65))
    await #expect(throws: BeadsError.noHandle("open the project first")) {
        _ = try await ws.send({ _ in }, op: "ready")
    }
}

@Test func lostBookmarkIsNoAccess() {
    #expect(throws: BeadsError.noAccess("the folder bookmark no longer resolves")) {
        _ = try Workspace(grantedFolder: CountingAccess(nil), relativePath: ".beads", engine: FakeEngine([:]))
    }
}

@Test func everyEngineCodeIsTyped() throws {
    let cases: [(String, BeadsError)] = [
        ("no_beads", .noBeads("m")), ("server_mode", .serverMode("m")), ("not_found", .notFound("m")),
        ("busy", .busy("m")), ("bad_request", .badRequest("m")), ("no_handle", .noHandle("m")), ("beads", .beads("m")),
    ]
    for (code, expected) in cases {
        let engine = FakeEngine(["x": [#"{"error":{"code":"\#(code)","message":"m"}}"#]])
        #expect(throws: expected) { _ = try engine.send(EngineRequest(op: "x")) }
    }
    let broken = FakeEngine(["x": ["not json"]])
    #expect { _ = try broken.send(EngineRequest(op: "x")) } throws: { error in
        if case BeadsError.undecodable = error { return true }
        return false
    }
}
