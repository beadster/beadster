import Foundation
import Testing
@testable import BeadsKit

private let opened = #"{"handle":1,"project":{"beads_dir":"/x/.beads","database":"x","mode":"embedded"}}"#
private func readyPage(_ items: [(String, Int, String)]) -> String {
    let rows = items.map { id, p, at in
        #"{"id":"\#(id)","title":"\#(id)","status":"open","priority":\#(p),"issue_type":"task","created_at":"\#(at)","updated_at":"\#(at)"}"#
    }
    return #"{"issues":[\#(rows.joined(separator: ","))]}"#
}

@Test func listsEveryKindAndCountsReady() async throws {
    let engine = FakeEngine([
        "open": [opened, #"{"error":{"code":"schema_behind","message":"m","db_version":60,"binary_version":65}}"#],
        "ready": [readyPage([("wa-1", 1, "2026-10-07T10:00:00Z"), ("wa-2", 2, "2026-10-07T10:00:00Z")])],
    ])
    let lib = ProjectLibrary(engine: engine)
    await lib.add(folderKey: "dev", access: PlainFolder(URL(fileURLWithPath: "/Users/x/Developer")), projects: [
        FoundProject(name: "wander", relativePath: "wander/.beads", kind: .embedded),
        FoundProject(name: "deepcalc", relativePath: "deepcalc/.beads", kind: .embedded),
        FoundProject(name: "old-blog", relativePath: "old-blog/.beads", kind: .legacy),
        FoundProject(name: "server", relativePath: "server/.beads", kind: .server),
    ])
    // the two embedded projects open in parallel: which got which answer is up to the scheduler
    let states = await lib.all.map(\.state)
    #expect(Set(states.map { "\($0)" }) == Set(["\(ProjectLibrary.State.ready(readyCount: 2))",
                                                "\(ProjectLibrary.State.needsMigration(dbVersion: 60, appVersion: 65))",
                                                "\(ProjectLibrary.State.legacy)", "\(ProjectLibrary.State.server)"]))
    #expect(await lib.all.map(\.found.name) == ["wander", "deepcalc", "old-blog", "server"]) // the order found is kept
    #expect(await lib.totalReady == 2)
    // the legacy and server projects were never opened
    #expect(engine.ops.filter { $0 == "open" }.count == 2)
}

@Test func readyEverywhereMergesByPriorityThenAge() async throws {
    let engine = FakeEngine([
        "open": [opened],
        "ready": [
            // read once each, at add: readyEverywhere asks nothing again
            readyPage([("wa-1", 2, "2026-10-07T09:00:00Z")]),
            readyPage([("dc-1", 0, "2026-10-07T11:00:00Z"), ("dc-2", 2, "2026-10-07T08:00:00Z")]),
        ],
    ])
    let lib = ProjectLibrary(engine: engine)
    let root = PlainFolder(URL(fileURLWithPath: "/Users/x/Developer"))
    await lib.add(folderKey: "dev", access: root, projects: [FoundProject(name: "wander", relativePath: "wander/.beads", kind: .embedded)])
    await lib.add(folderKey: "dev", access: root, projects: [FoundProject(name: "deepcalc", relativePath: "deepcalc/.beads", kind: .embedded)])
    let readsBefore = engine.ops.filter { $0 == "ready" }.count
    let merged = await lib.readyEverywhere()
    #expect(engine.ops.filter { $0 == "ready" }.count == readsBefore)
    #expect(merged.map(\.bead.id) == ["dc-1", "dc-2", "wa-1"])
    #expect(merged.map(\.project.found.name) == ["deepcalc", "deepcalc", "wander"])
}

@Test func removingAFolderClosesItsProjects() async throws {
    let engine = FakeEngine(["open": [opened], "ready": [readyPage([])], "close": ["{}"]])
    let lib = ProjectLibrary(engine: engine)
    await lib.add(folderKey: "dev", access: PlainFolder(URL(fileURLWithPath: "/d")), projects: [
        FoundProject(name: "a", relativePath: "a/.beads", kind: .embedded),
    ])
    await lib.remove(folderKey: "dev")
    #expect(await lib.all.isEmpty)
    #expect(engine.ops.last == "close")
}

@Test func previewCountsWithoutKeepingAnythingOpen() async throws {
    let engine = FakeEngine(["open": [opened], "ready": [readyPage([("wa-1", 1, "2026-10-07T10:00:00Z")])], "close": ["{}"]])
    let lib = ProjectLibrary(engine: engine)
    let states = await lib.preview(access: PlainFolder(URL(fileURLWithPath: "/d")), projects: [
        FoundProject(name: "wander", relativePath: "wander/.beads", kind: .embedded),
        FoundProject(name: "old", relativePath: "old/.beads", kind: .legacy),
    ])
    #expect(states["wander/.beads"] == .ready(readyCount: 1))
    #expect(states["old/.beads"] == .legacy)
    #expect(await lib.all.isEmpty)
    #expect(engine.ops == ["open", "ready", "close"])
}

@Test func excludedProjectsStayOut() throws {
    let found = [FoundProject(name: "a", relativePath: "a/.beads", kind: .embedded),
                 FoundProject(name: "b", relativePath: "b/.beads", kind: .embedded)]
    let folder = GrantedFolder(key: "k", path: "/d", excluded: ["b/.beads"])
    #expect(folder.included(found).map(\.name) == ["a"])
}

@Test func aProjectThatStopsOpeningSaysWhyAndAnUpgradeOpensIt() async throws {
    let behind = #"{"error":{"code":"schema_behind","message":"m","db_version":60,"binary_version":65}}"#
    let busy = #"{"error":{"code":"busy","message":"locked by pid 41"}}"#
    let engine = FakeEngine(["open": [behind, busy, opened], "migrate": ["{}"],
                             "ready": [readyPage([("wa-1", 1, "2026-10-07T10:00:00Z")])],
                             "list": [readPageEmpty]])
    let lib = ProjectLibrary(engine: engine)
    await lib.add(folderKey: "dev", access: PlainFolder(URL(fileURLWithPath: "/d")), projects: [
        FoundProject(name: "a", relativePath: "a/.beads", kind: .embedded),
    ])
    let id = try #require(await lib.all.first?.id)
    #expect(await lib.all.first?.state == .needsMigration(dbVersion: 60, appVersion: 65))
    await lib.refresh(id)
    #expect(await lib.all.first?.state == .failed(.busy("locked by pid 41")))
    await lib.upgrade(id)
    #expect(await lib.all.first?.state == .ready(readyCount: 1))
    #expect(engine.ops.contains("migrate"))
    #expect(await lib.hasBeads(id)) // ready rows answer without asking
}

private let readPageEmpty = #"{"issues":[]}"#

@Test func aProjectWithNoBeadsAtAllIsToldApartFromNothingReady() async throws {
    let engine = FakeEngine(["open": [opened], "ready": [readyPage([])], "list": [#"{"issues":[]}"#]])
    let lib = ProjectLibrary(engine: engine)
    await lib.add(folderKey: "dev", access: PlainFolder(URL(fileURLWithPath: "/d")), projects: [
        FoundProject(name: "a", relativePath: "a/.beads", kind: .embedded),
    ])
    let id = try #require(await lib.all.first?.id)
    #expect(await lib.hasBeads(id) == false)
    #expect(engine.ops.last == "list")
}

@Test func needsYouAgentsAndSpotlightShareOneListPerProject() async throws {
    let open = #"{"issues":[{"id":"a-1","title":"Mine","status":"open","priority":1,"issue_type":"task","assignee":"you","created_at":"2026-10-07T10:00:00Z","updated_at":"2026-10-07T10:00:00Z"},{"id":"a-2","title":"Theirs","status":"in_progress","priority":1,"issue_type":"task","assignee":"claude-1","created_at":"2026-10-07T10:00:00Z","updated_at":"2026-10-07T10:00:00Z"}]}"#
    let engine = FakeEngine(["open": [opened], "ready": [readyPage([])], "list": [open]])
    let lib = ProjectLibrary(engine: engine)
    await lib.add(folderKey: "dev", access: PlainFolder(URL(fileURLWithPath: "/d")), projects: [
        FoundProject(name: "a", relativePath: "a/.beads", kind: .embedded),
    ])
    let id = try #require(await lib.all.first?.id)
    #expect(await lib.needsYou("you").assigned.map(\.bead.id) == ["a-1"])
    #expect(await lib.workingEverywhere().map(\.bead.id) == ["a-2"])
    #expect(await lib.openBeads(id).count == 2)
    #expect(engine.ops.filter { $0 == "list" }.count == 1)
    // a change drops the snapshot: the next read lists again
    await lib.refresh(id)
    _ = await lib.workingEverywhere()
    #expect(engine.ops.filter { $0 == "list" }.count == 2)
}
