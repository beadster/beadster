//
//  BeadsDatabaseTests.swift
//  Beadster
//
//  Unit tests for BeadsDatabase
//

import XCTest
import SQLite3
@testable import Shared

final class BeadsDatabaseTests: XCTestCase {

    var tempDir: URL!
    var dbPath: String!

    override func setUp() {
        super.setUp()
        // Create a temporary directory and database
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Create .beads directory
        let beadsDir = tempDir.appendingPathComponent(".beads")
        try? FileManager.default.createDirectory(at: beadsDir, withIntermediateDirectories: true)

        // Database name should match project name (using temp dir name as project)
        let projectName = tempDir.lastPathComponent
        dbPath = beadsDir.appendingPathComponent("\(projectName).db").path

        // Create and initialize database
        try? createTestDatabase()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Helper Methods

    private func createTestDatabase() throws {
        var db: OpaquePointer?
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
            throw DatabaseError.cantOpen
        }
        defer { sqlite3_close(db) }

        // Create schema
        let schema = """
        CREATE TABLE issues (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            description TEXT,
            status TEXT NOT NULL DEFAULT 'open',
            priority INTEGER NOT NULL DEFAULT 2,
            issue_type TEXT NOT NULL DEFAULT 'task',
            created_at DATETIME NOT NULL,
            updated_at DATETIME NOT NULL
        );

        CREATE TABLE labels (
            issue_id TEXT NOT NULL,
            label TEXT NOT NULL,
            PRIMARY KEY (issue_id, label),
            FOREIGN KEY (issue_id) REFERENCES issues(id) ON DELETE CASCADE
        );

        CREATE TABLE dependencies (
            issue_id TEXT NOT NULL,
            depends_on_id TEXT NOT NULL,
            type TEXT NOT NULL DEFAULT 'blocks',
            created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
            created_by TEXT NOT NULL,
            PRIMARY KEY (issue_id, depends_on_id),
            FOREIGN KEY (issue_id) REFERENCES issues(id) ON DELETE CASCADE,
            FOREIGN KEY (depends_on_id) REFERENCES issues(id) ON DELETE CASCADE
        );
        """

        guard sqlite3_exec(db, schema, nil, nil, nil) == SQLITE_OK else {
            throw DatabaseError.queryFailed
        }
    }

    private func insertIssue(id: String, title: String, description: String? = nil,
                            status: String = "open", priority: Int = 2, issueType: String = "task",
                            createdAt: String = "2025-10-28T12:00:00Z",
                            updatedAt: String = "2025-10-28T12:00:00Z") throws {
        var db: OpaquePointer?
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
            throw DatabaseError.cantOpen
        }
        defer { sqlite3_close(db) }

        let sql = """
        INSERT INTO issues (id, title, description, status, priority, issue_type, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.queryFailed
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, (id as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 2, (title as NSString).utf8String, -1, nil)
        if let desc = description {
            sqlite3_bind_text(statement, 3, (desc as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(statement, 3)
        }
        sqlite3_bind_text(statement, 4, (status as NSString).utf8String, -1, nil)
        sqlite3_bind_int(statement, 5, Int32(priority))
        sqlite3_bind_text(statement, 6, (issueType as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 7, (createdAt as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 8, (updatedAt as NSString).utf8String, -1, nil)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.queryFailed
        }
    }

    private func insertLabel(issueId: String, label: String) throws {
        var db: OpaquePointer?
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
            throw DatabaseError.cantOpen
        }
        defer { sqlite3_close(db) }

        let sql = "INSERT INTO labels (issue_id, label) VALUES (?, ?)"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.queryFailed
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, (issueId as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 2, (label as NSString).utf8String, -1, nil)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.queryFailed
        }
    }

    private func insertDependency(issueId: String, dependsOnId: String, type: String = "blocks") throws {
        var db: OpaquePointer?
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
            throw DatabaseError.cantOpen
        }
        defer { sqlite3_close(db) }

        let sql = "INSERT INTO dependencies (issue_id, depends_on_id, type, created_by) VALUES (?, ?, ?, 'test')"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.queryFailed
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, (issueId as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 2, (dependsOnId as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 3, (type as NSString).utf8String, -1, nil)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.queryFailed
        }
    }

    // MARK: - Tests

    func testOpenAndCloseDatabase() throws {
        let db = BeadsDatabase(beadsDir: tempDir.path)

        XCTAssertNoThrow(try db.open(), "Should open database without error")
        db.close()
    }

    func testGetAllIssuesEmpty() throws {
        let db = BeadsDatabase(beadsDir: tempDir.path)
        try db.open()
        defer { db.close() }

        let issues = try db.getAllIssues()

        XCTAssertEqual(issues.count, 0, "Should return empty array for empty database")
    }

    func testGetAllIssuesSingle() throws {
        try insertIssue(id: "test-1", title: "Test Issue", description: "Test description")

        let db = BeadsDatabase(beadsDir: tempDir.path)
        try db.open()
        defer { db.close() }

        let issues = try db.getAllIssues()

        XCTAssertEqual(issues.count, 1, "Should return one issue")
        XCTAssertEqual(issues[0].id, "test-1")
        XCTAssertEqual(issues[0].title, "Test Issue")
        XCTAssertEqual(issues[0].body, "Test description")
        XCTAssertEqual(issues[0].status, "open")
        XCTAssertEqual(issues[0].priority, 2)
    }

    func testGetAllIssuesMultiple() throws {
        try insertIssue(id: "test-1", title: "Issue 1", priority: 0)
        try insertIssue(id: "test-2", title: "Issue 2", priority: 1)
        try insertIssue(id: "test-3", title: "Issue 3", priority: 2)

        let db = BeadsDatabase(beadsDir: tempDir.path)
        try db.open()
        defer { db.close() }

        let issues = try db.getAllIssues()

        XCTAssertEqual(issues.count, 3, "Should return all three issues")
        XCTAssertTrue(issues.contains(where: { $0.id == "test-1" }))
        XCTAssertTrue(issues.contains(where: { $0.id == "test-2" }))
        XCTAssertTrue(issues.contains(where: { $0.id == "test-3" }))
    }

    func testGetAllIssuesWithLabels() throws {
        try insertIssue(id: "test-1", title: "Issue with labels")
        try insertLabel(issueId: "test-1", label: "bug")
        try insertLabel(issueId: "test-1", label: "urgent")
        try insertLabel(issueId: "test-1", label: "-x-session:abc123")

        let db = BeadsDatabase(beadsDir: tempDir.path)
        try db.open()
        defer { db.close() }

        let issues = try db.getAllIssues()

        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues[0].labels.count, 3, "Should have 3 labels")
        XCTAssertTrue(issues[0].labels.contains("bug"))
        XCTAssertTrue(issues[0].labels.contains("urgent"))
        XCTAssertEqual(issues[0].sessionId, "abc123", "Should extract session ID from label")
    }

    func testGetAllIssuesExtractMetadataLabels() throws {
        try insertIssue(id: "test-1", title: "Issue with metadata")
        try insertLabel(issueId: "test-1", label: "-x-session:session123")
        try insertLabel(issueId: "test-1", label: "-x-client:macos")
        try insertLabel(issueId: "test-1", label: "-x-project:myproject")

        let db = BeadsDatabase(beadsDir: tempDir.path)
        try db.open()
        defer { db.close() }

        let issues = try db.getAllIssues()

        XCTAssertEqual(issues[0].sessionId, "session123")
        XCTAssertEqual(issues[0].client, "macos")
        XCTAssertEqual(issues[0].projectName, "myproject")
    }

    func testGetIssuesById() throws {
        try insertIssue(id: "test-1", title: "Issue 1")
        try insertIssue(id: "test-2", title: "Issue 2")
        try insertIssue(id: "test-3", title: "Issue 3")

        let db = BeadsDatabase(beadsDir: tempDir.path)
        try db.open()
        defer { db.close() }

        let issues = try db.getIssues(ids: ["test-1", "test-3"])

        XCTAssertEqual(issues.count, 2, "Should return only requested issues")
        XCTAssertTrue(issues.contains(where: { $0.id == "test-1" }))
        XCTAssertTrue(issues.contains(where: { $0.id == "test-3" }))
        XCTAssertFalse(issues.contains(where: { $0.id == "test-2" }))
    }

    func testGetIssuesByIdEmpty() throws {
        let db = BeadsDatabase(beadsDir: tempDir.path)
        try db.open()
        defer { db.close() }

        let issues = try db.getIssues(ids: [])

        XCTAssertEqual(issues.count, 0, "Should return empty array for empty ID list")
    }

    func testGetIssuesByIdNonExistent() throws {
        try insertIssue(id: "test-1", title: "Issue 1")

        let db = BeadsDatabase(beadsDir: tempDir.path)
        try db.open()
        defer { db.close() }

        let issues = try db.getIssues(ids: ["nonexistent"])

        XCTAssertEqual(issues.count, 0, "Should return empty array for non-existent IDs")
    }

    func testIssueExists() throws {
        try insertIssue(id: "test-1", title: "Issue 1")

        let db = BeadsDatabase(beadsDir: tempDir.path)
        try db.open()
        defer { db.close() }

        XCTAssertTrue(try db.issueExists(beadsId: "test-1"), "Should return true for existing issue")
        XCTAssertFalse(try db.issueExists(beadsId: "nonexistent"), "Should return false for non-existent issue")
    }

    func testGetAllDependencies() throws {
        try insertIssue(id: "test-1", title: "Blocked Issue")
        try insertIssue(id: "test-2", title: "Blocker Issue")
        try insertDependency(issueId: "test-1", dependsOnId: "test-2", type: "blocks")

        let db = BeadsDatabase(beadsDir: tempDir.path)
        try db.open()
        defer { db.close() }

        let deps = try db.getAllDependencies()

        XCTAssertEqual(deps.count, 1, "Should return one dependency")
        XCTAssertEqual(deps[0].issueId, "test-1")
        XCTAssertEqual(deps[0].dependsOnId, "test-2")
        XCTAssertEqual(deps[0].type, "blocks")
    }

    func testGetAllDependenciesMultiple() throws {
        try insertIssue(id: "test-1", title: "Issue 1")
        try insertIssue(id: "test-2", title: "Issue 2")
        try insertIssue(id: "test-3", title: "Issue 3")
        try insertDependency(issueId: "test-1", dependsOnId: "test-2", type: "blocks")
        try insertDependency(issueId: "test-1", dependsOnId: "test-3", type: "blocks")
        try insertDependency(issueId: "test-2", dependsOnId: "test-3", type: "parent-child")

        let db = BeadsDatabase(beadsDir: tempDir.path)
        try db.open()
        defer { db.close() }

        let deps = try db.getAllDependencies()

        XCTAssertEqual(deps.count, 3, "Should return all three dependencies")
        XCTAssertTrue(deps.contains(where: { $0.issueId == "test-1" && $0.dependsOnId == "test-2" }))
        XCTAssertTrue(deps.contains(where: { $0.issueId == "test-1" && $0.dependsOnId == "test-3" }))
        XCTAssertTrue(deps.contains(where: { $0.issueId == "test-2" && $0.dependsOnId == "test-3" && $0.type == "parent-child" }))
    }

    func testGetAllDependenciesEmpty() throws {
        let db = BeadsDatabase(beadsDir: tempDir.path)
        try db.open()
        defer { db.close() }

        let deps = try db.getAllDependencies()

        XCTAssertEqual(deps.count, 0, "Should return empty array when no dependencies")
    }

    func testDateParsing() throws {
        // Test that dates in Go format are parsed correctly
        let goFormatDate = "2025-10-28 12:30:45.123456 +0200 CEST"
        try insertIssue(id: "test-1", title: "Date test", createdAt: goFormatDate, updatedAt: goFormatDate)

        let db = BeadsDatabase(beadsDir: tempDir.path)
        try db.open()
        defer { db.close() }

        let issues = try db.getAllIssues()

        XCTAssertEqual(issues.count, 1)
        // Just verify we got a reasonable timestamp (not 0, not current time)
        XCTAssertGreaterThan(issues[0].createdAt, 1700000000, "Should parse date to reasonable timestamp")
        XCTAssertLessThan(issues[0].createdAt, 2000000000, "Should parse date to reasonable timestamp")
    }

    func testIssueWithNullDescription() throws {
        try insertIssue(id: "test-1", title: "No description", description: nil)

        let db = BeadsDatabase(beadsDir: tempDir.path)
        try db.open()
        defer { db.close() }

        let issues = try db.getAllIssues()

        XCTAssertEqual(issues.count, 1)
        XCTAssertNil(issues[0].body, "Should handle NULL description")
    }

    func testIssueWithDifferentStatuses() throws {
        try insertIssue(id: "test-1", title: "Open", status: "open")
        try insertIssue(id: "test-2", title: "In Progress", status: "in_progress")
        try insertIssue(id: "test-3", title: "Closed", status: "closed")
        try insertIssue(id: "test-4", title: "Blocked", status: "blocked")

        let db = BeadsDatabase(beadsDir: tempDir.path)
        try db.open()
        defer { db.close() }

        let issues = try db.getAllIssues()

        XCTAssertEqual(issues.count, 4)
        let statuses = Set(issues.map { $0.status })
        XCTAssertTrue(statuses.contains("open"))
        XCTAssertTrue(statuses.contains("in_progress"))
        XCTAssertTrue(statuses.contains("closed"))
        XCTAssertTrue(statuses.contains("blocked"))
    }

    func testIssueWithDifferentPriorities() throws {
        try insertIssue(id: "test-1", title: "P0", priority: 0)
        try insertIssue(id: "test-2", title: "P1", priority: 1)
        try insertIssue(id: "test-3", title: "P2", priority: 2)
        try insertIssue(id: "test-4", title: "P3", priority: 3)
        try insertIssue(id: "test-5", title: "P4", priority: 4)

        let db = BeadsDatabase(beadsDir: tempDir.path)
        try db.open()
        defer { db.close() }

        let issues = try db.getAllIssues()

        XCTAssertEqual(issues.count, 5)
        let priorities = Set(issues.map { $0.priority })
        XCTAssertEqual(priorities, Set([0, 1, 2, 3, 4]))
    }

    func testIssueWithDifferentTypes() throws {
        try insertIssue(id: "test-1", title: "Bug", issueType: "bug")
        try insertIssue(id: "test-2", title: "Feature", issueType: "feature")
        try insertIssue(id: "test-3", title: "Task", issueType: "task")
        try insertIssue(id: "test-4", title: "Epic", issueType: "epic")
        try insertIssue(id: "test-5", title: "Chore", issueType: "chore")

        let db = BeadsDatabase(beadsDir: tempDir.path)
        try db.open()
        defer { db.close() }

        let issues = try db.getAllIssues()

        XCTAssertEqual(issues.count, 5)
        // Note: issueType is not used in current Issue model but query still works
    }
}
