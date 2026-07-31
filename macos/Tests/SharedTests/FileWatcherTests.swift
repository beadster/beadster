import XCTest
@testable import Shared

final class FileWatcherTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("beadster-filewatcher-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
    }

    func testDirectoryWatcherDetectsIssuesJSONLAppend() throws {
        let beadsDir = try makeBeadsDirectory()
        let issuesFile = beadsDir.appendingPathComponent("issues.jsonl")
        try validIssueLine(id: "existing").write(to: issuesFile, atomically: true, encoding: .utf8)

        let event = expectation(description: "Detected append to issues.jsonl")
        let watcher = FileWatcher(path: beadsDir.path, latency: 0.1) {
            event.fulfill()
        }
        watcher.start()
        defer { watcher.stop() }

        Thread.sleep(forTimeInterval: 0.2)
        let handle = try FileHandle(forWritingTo: issuesFile)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(validIssueLine(id: "appended").utf8))
        try handle.close()

        wait(for: [event], timeout: 3.0)
    }

    func testDirectoryWatcherDetectsAtomicIssuesJSONLReplacement() throws {
        let beadsDir = try makeBeadsDirectory()
        let issuesFile = beadsDir.appendingPathComponent("issues.jsonl")
        try validIssueLine(id: "existing").write(to: issuesFile, atomically: true, encoding: .utf8)

        let event = expectation(description: "Detected atomic replacement of issues.jsonl")
        let watcher = FileWatcher(path: beadsDir.path, latency: 0.1) {
            event.fulfill()
        }
        watcher.start()
        defer { watcher.stop() }

        Thread.sleep(forTimeInterval: 0.2)
        try (validIssueLine(id: "existing") + validIssueLine(id: "replacement"))
            .write(to: issuesFile, atomically: true, encoding: .utf8)

        wait(for: [event], timeout: 3.0)
    }

    func testDirectoryWatcherDetectsIssuesJSONLCreation() throws {
        let beadsDir = try makeBeadsDirectory()
        let issuesFile = beadsDir.appendingPathComponent("issues.jsonl")

        let event = expectation(description: "Detected creation of issues.jsonl")
        let watcher = FileWatcher(path: beadsDir.path, latency: 0.1) {
            event.fulfill()
        }
        watcher.start()
        defer { watcher.stop() }

        Thread.sleep(forTimeInterval: 0.2)
        try validIssueLine(id: "created").write(to: issuesFile, atomically: true, encoding: .utf8)

        wait(for: [event], timeout: 3.0)
    }

    private func makeBeadsDirectory() throws -> URL {
        let beadsDir = tempDir.appendingPathComponent(".beads", isDirectory: true)
        try FileManager.default.createDirectory(at: beadsDir, withIntermediateDirectories: true)
        return beadsDir
    }

    private func validIssueLine(id: String) -> String {
        """
        {"id":"\(id)","title":"External feature issue","description":"Created outside Beadster","status":"open","priority":2,"type":"feature","labels":["watcher-test"],"created_at":"2026-07-31T12:00:00Z","updated_at":"2026-07-31T12:00:00Z"}

        """
    }
}
