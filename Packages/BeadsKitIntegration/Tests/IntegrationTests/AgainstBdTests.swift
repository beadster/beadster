import BeadsFFIEngine
import BeadsKit
import Foundation
import Testing

// Every fixture was made by bd 1.3.1 (macos/BeadsFFI/fixtures.sh), and its expected/ folder
// holds what bd --json said about it. BeadsKit through the real engine must say the same.
let fixtures = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".cache/beadster/fixtures")
let names = ["empty", "one", "links", "gates", "workflow", "memories", "claims", "many"]

/// A private copy of a fixture, so writes never touch the shared one.
func copy(_ name: String) throws -> URL {
    let to = FileManager.default.temporaryDirectory.appending(path: "k7-\(UUID().uuidString)/\(name)")
    try FileManager.default.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.copyItem(at: fixtures.appending(path: name), to: to)
    return to
}

func open(_ folder: URL) async throws -> Workspace {
    let ws = try Workspace(grantedFolder: PlainFolder(folder), relativePath: ".beads", engine: BeadsFFIEngine())
    #expect(try await ws.open() == .ready)
    return ws
}

func expected(_ name: String, _ file: String) throws -> [Bead] {
    try BeadsJSON.decoder().decode([Bead].self, from: Data(contentsOf: fixtures.appending(path: "\(name)/expected/\(file)")))
}

/// Field by field, with the field named when it differs.
func same(_ a: Bead, _ b: Bead, _ context: String) {
    let pairs: [(String, String, String)] = [
        ("title", a.title, b.title), ("status", a.status.rawValue, b.status.rawValue),
        ("priority", "\(a.priority)", "\(b.priority)"), ("type", a.type.rawValue, b.type.rawValue),
        ("assignee", a.assignee ?? "", b.assignee ?? ""), ("description", a.description ?? "", b.description ?? ""),
        ("design", a.design ?? "", b.design ?? ""), ("acceptance", a.acceptanceCriteria ?? "", b.acceptanceCriteria ?? ""),
        ("labels", a.labels.sorted().joined(separator: ","), b.labels.sorted().joined(separator: ",")),
        ("parent", a.parent ?? "", b.parent ?? ""), ("createdAt", "\(a.createdAt)", "\(b.createdAt)"),
        ("updatedAt", "\(a.updatedAt)", "\(b.updatedAt)"), ("closedAt", "\(String(describing: a.closedAt))", "\(String(describing: b.closedAt))"),
        ("closeReason", a.closeReason ?? "", b.closeReason ?? ""), ("lease", "\(String(describing: a.leaseExpiresAt))", "\(String(describing: b.leaseExpiresAt))"),
        ("dependencyCount", "\(a.dependencyCount)", "\(b.dependencyCount)"), ("dependentCount", "\(a.dependentCount)", "\(b.dependentCount)"),
        ("commentCount", "\(a.commentCount)", "\(b.commentCount)"),
    ]
    for (field, x, y) in pairs where x != y {
        Issue.record("\(context) \(a.id).\(field): app '\(x)' vs bd '\(y)'")
    }
}

@Test(arguments: names)
func listMatchesBd(_ name: String) async throws {
    let ws = try await open(try copy(name))
    let mine = try await ws.list(BeadFilter(limit: 0, includeClosed: true)).beads
    let bd = try expected(name, "list-all.json")
    #expect(Set(mine.map(\.id)) == Set(bd.map(\.id)), "\(name): ids differ")
    let byID = Dictionary(uniqueKeysWithValues: mine.map { ($0.id, $0) })
    for b in bd { if let m = byID[b.id] { same(m, b, "\(name) list") } }
    await ws.close()
}

@Test(arguments: names)
func readyMatchesBd(_ name: String) async throws {
    let ws = try await open(try copy(name))
    let mine = try await ws.ready(limit: 0).beads
    let bd = try expected(name, "ready.json")
    if mine.map(\.id) != bd.map(\.id) {
        let i = (0..<min(mine.count, bd.count)).first { mine[$0].id != bd[$0].id } ?? min(mine.count, bd.count)
        var detail = "app \(mine.count) vs bd \(bd.count), first difference at \(i)"
        if i < mine.count, i < bd.count {
            let m = mine[i], o = bd[i]
            detail += ": app \(m.id) P\(m.priority) \(m.createdAt), bd \(o.id) P\(o.priority) \(o.createdAt)"
        }
        Issue.record("\(name) ready: \(detail)")
    }
    await ws.close()
}

@Test func showMatchesBdForEveryShownBead() async throws {
    for name in names {
        let dir = fixtures.appending(path: "\(name)/expected")
        let shows = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasPrefix("show-") }
        guard !shows.isEmpty else { continue }
        let ws = try await open(try copy(name))
        for file in shows {
            let bd = try #require(try expected(name, file).first)
            let mine = try await ws.show(bd.id)
            same(mine, bd, "\(name) show")
            #expect(Set(mine.dependencies.map(\.id)) == Set(bd.dependencies.map(\.id)), "\(bd.id) dependencies")
            #expect(Set(mine.dependents.map(\.id)) == Set(bd.dependents.map(\.id)), "\(bd.id) dependents")
            #expect(mine.comments.map(\.text) == bd.comments.map(\.text), "\(bd.id) comments")
        }
        await ws.close()
    }
}

@Test func memoriesMatchBd() async throws {
    let ws = try await open(try copy("memories"))
    let bd = try Memory.decodeList(Data(contentsOf: fixtures.appending(path: "memories/expected/memories.json")))
    #expect(try await ws.memories() == bd)
}

@Test func gatesFixtureNeedsYou() async throws {
    let ws = try await open(try copy("gates"))
    let gates = try await ws.gates()
    let human = try #require(gates.first { $0.needsAPerson })
    #expect(human.title == "Deploy to production")
    #expect(human.reason == "Approve the deploy")
    #expect(gates.filter { !$0.needsAPerson }.map(\.title) == ["Ship after review"])
    await ws.close()
}
