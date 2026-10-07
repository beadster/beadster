import Foundation
import Testing
@testable import BeadsKit

/// A temporary folder tree; `beads` lists the .beads layouts to create.
private func tree(_ beads: [String: [String]], extra: [String] = []) throws -> URL {
    let root = FileManager.default.temporaryDirectory.appending(path: "scan-\(UUID().uuidString)/Developer")
    for (path, files) in beads {
        let dir = root.appending(path: path)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for f in files {
            let url = dir.appending(path: f)
            if f.hasSuffix("/") {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            } else {
                try Data(f == "metadata.json" ? #"{"dolt_mode":"server"}"#.utf8 : "x".utf8).write(to: url)
            }
        }
    }
    for e in extra {
        try FileManager.default.createDirectory(at: root.appending(path: e), withIntermediateDirectories: true)
    }
    return root
}

@Test func findsEveryKindAndSkipsTheNoise() throws {
    let root = try tree([
        "wander/.beads": ["embeddeddolt/", "config.yaml"],
        "work/deepcalc/.beads": ["metadata.json", "config.yaml"],
        "old-blog/.beads": ["old-blog.db", "issues.jsonl"],
        "tinydot/node_modules/pkg/.beads": ["embeddeddolt/"],
        "tinydot/.git/x/.beads": ["embeddeddolt/"],
        "empty/.beads": ["README.md"],
        "a/b/c/d/e/f/.beads": ["embeddeddolt/"],
    ])
    let found = ProjectScanner.scan(root)
    #expect(found.map(\.name) == ["deepcalc", "old-blog", "wander"])
    #expect(found.first { $0.name == "wander" }?.kind == .embedded)
    #expect(found.first { $0.name == "wander" }?.relativePath == "wander/.beads")
    #expect(found.first { $0.name == "deepcalc" }?.kind == .server)
    #expect(found.first { $0.name == "deepcalc" }?.relativePath == "work/deepcalc/.beads")
    #expect(found.first { $0.name == "old-blog" }?.kind == .legacy)
}

@Test func theGrantedFolderCanBeTheProject() throws {
    let root = try tree([".beads": ["embeddeddolt/"]])
    let found = ProjectScanner.scan(root)
    #expect(found.map(\.relativePath) == [".beads"])
    #expect(found.first?.name == "Developer")
}

@Test func depthLimitIsADepthLimit() throws {
    let root = try tree(["a/b/c/d/.beads": ["embeddeddolt/"]])
    #expect(ProjectScanner.scan(root, maxDepth: 4).count == 1)
    #expect(ProjectScanner.scan(root, maxDepth: 2).isEmpty)
}

@Test func realFixtureIsEmbedded() throws {
    let fixtures = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".cache/beadster/fixtures")
    try #require(FileManager.default.fileExists(atPath: fixtures.path), "run macos/BeadsFFI/fixtures.sh")
    let found = ProjectScanner.scan(fixtures, maxDepth: 1)
    #expect(found.count == 8)
    #expect(found.allSatisfy { $0.kind == .embedded })
}

@Test func folderHealth() throws {
    let root = try tree([:], extra: ["moved-here"])
    let f = GrantedFolder(key: "k", path: root.path)
    #expect(f.health(resolvedPath: root.path) == .ok)
    let moved = root.appending(path: "moved-here").path
    #expect(f.health(resolvedPath: moved) == .moved(to: moved))
    #expect(f.health(resolvedPath: nil) == .missing)
    #expect(f.health(resolvedPath: "/nonexistent/path") == .missing)
}
