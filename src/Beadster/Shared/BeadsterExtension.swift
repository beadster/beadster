import Foundation
import SQLite3

/// Manages beadster extension tables in .beads/beads.db
/// Following beads EXTENDING.md pattern: add custom tables with beadster_ prefix
class BeadsterExtension {
    private let dbPath: String
    private var db: OpaquePointer?

    init(beadsDir: String) {
        self.dbPath = "\(beadsDir)/.beads/beads.db"
    }

    /// Initialize beadster extension tables in beads.db
    func initialize() throws {
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
            throw ExtensionError.cantOpen
        }
        defer {
            sqlite3_close(db)
        }

        // Create beadster_sync table
        let syncTableSQL = """
        CREATE TABLE IF NOT EXISTS beadster_sync (
          issue_id TEXT PRIMARY KEY,
          cloud_id TEXT NOT NULL,
          synced_at INTEGER NOT NULL,
          cloud_updated_at INTEGER,
          local_updated_at INTEGER,
          sync_status TEXT DEFAULT 'synced',
          last_error TEXT,
          FOREIGN KEY (issue_id) REFERENCES issues(id) ON DELETE CASCADE
        );

        CREATE INDEX IF NOT EXISTS idx_beadster_sync_cloud_id
          ON beadster_sync(cloud_id);
        CREATE INDEX IF NOT EXISTS idx_beadster_sync_status
          ON beadster_sync(sync_status);
        """

        guard sqlite3_exec(db, syncTableSQL, nil, nil, nil) == SQLITE_OK else {
            throw ExtensionError.createFailed
        }

        // Create beadster_source table (source-level metadata)
        let sourceTableSQL = """
        CREATE TABLE IF NOT EXISTS beadster_source (
          id TEXT PRIMARY KEY DEFAULT '1',
          source_id TEXT,
          last_full_sync INTEGER,
          last_pull INTEGER,
          last_push INTEGER
        );
        """

        guard sqlite3_exec(db, sourceTableSQL, nil, nil, nil) == SQLITE_OK else {
            throw ExtensionError.createFailed
        }

        print("✅ beadster extension tables initialized")
    }

    /// Get sync info for an issue
    func getSyncInfo(issueId: String) throws -> SyncInfo? {
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
            throw ExtensionError.cantOpen
        }
        defer {
            sqlite3_close(db)
        }

        let query = """
        SELECT cloud_id, synced_at, cloud_updated_at, local_updated_at, sync_status
        FROM beadster_sync
        WHERE issue_id = ?
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            throw ExtensionError.queryFailed
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, (issueId as NSString).utf8String, -1, nil)

        if sqlite3_step(statement) == SQLITE_ROW {
            let cloudId = String(cString: sqlite3_column_text(statement, 0))
            let syncedAt = Int(sqlite3_column_int64(statement, 1))
            let cloudUpdatedAt = sqlite3_column_type(statement, 2) != SQLITE_NULL
                ? Int(sqlite3_column_int64(statement, 2)) : nil
            let localUpdatedAt = sqlite3_column_type(statement, 3) != SQLITE_NULL
                ? Int(sqlite3_column_int64(statement, 3)) : nil
            let syncStatus = String(cString: sqlite3_column_text(statement, 4))

            return SyncInfo(
                issueId: issueId,
                cloudId: cloudId,
                syncedAt: syncedAt,
                cloudUpdatedAt: cloudUpdatedAt,
                localUpdatedAt: localUpdatedAt,
                syncStatus: syncStatus
            )
        }

        return nil
    }

    /// Record that issue was synced
    func recordSync(issueId: String, cloudId: String, localUpdatedAt: Int, cloudUpdatedAt: Int) throws {
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
            throw ExtensionError.cantOpen
        }
        defer {
            sqlite3_close(db)
        }

        let sql = """
        INSERT INTO beadster_sync (
          issue_id, cloud_id, synced_at, local_updated_at, cloud_updated_at, sync_status
        )
        VALUES (?, ?, ?, ?, ?, 'synced')
        ON CONFLICT(issue_id) DO UPDATE SET
          cloud_id = excluded.cloud_id,
          synced_at = excluded.synced_at,
          local_updated_at = excluded.local_updated_at,
          cloud_updated_at = excluded.cloud_updated_at,
          sync_status = 'synced',
          last_error = NULL
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw ExtensionError.updateFailed
        }
        defer { sqlite3_finalize(statement) }

        let now = Int(Date().timeIntervalSince1970)

        sqlite3_bind_text(statement, 1, (issueId as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 2, (cloudId as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(statement, 3, Int64(now))
        sqlite3_bind_int64(statement, 4, Int64(localUpdatedAt))
        sqlite3_bind_int64(statement, 5, Int64(cloudUpdatedAt))

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw ExtensionError.updateFailed
        }
    }

    /// Get cloud ID for local issue ID
    func getCloudId(issueId: String) throws -> String? {
        return try getSyncInfo(issueId: issueId)?.cloudId
    }

    /// Get issues that need syncing (modified since last sync)
    func getUnsyncedIssues() throws -> [String] {
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
            throw ExtensionError.cantOpen
        }
        defer {
            sqlite3_close(db)
        }

        let query = """
        SELECT i.id
        FROM issues i
        LEFT JOIN beadster_sync s ON s.issue_id = i.id
        WHERE s.synced_at IS NULL
           OR s.local_updated_at < i.updated_at
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            throw ExtensionError.queryFailed
        }
        defer { sqlite3_finalize(statement) }

        var issueIds: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let issueId = String(cString: sqlite3_column_text(statement, 0))
            issueIds.append(issueId)
        }

        return issueIds
    }

    /// Update source-level metadata
    func updateSourceMeta(sourceId: String, lastPull: Int? = nil, lastPush: Int? = nil) throws {
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
            throw ExtensionError.cantOpen
        }
        defer {
            sqlite3_close(db)
        }

        // Upsert source meta
        var sql = """
        INSERT INTO beadster_source (id, source_id"""

        if lastPull != nil {
            sql += ", last_pull"
        }
        if lastPush != nil {
            sql += ", last_push"
        }

        sql += ")\nVALUES ('1', ?"

        if lastPull != nil {
            sql += ", ?"
        }
        if lastPush != nil {
            sql += ", ?"
        }

        sql += ")\nON CONFLICT(id) DO UPDATE SET\n  source_id = excluded.source_id"

        if lastPull != nil {
            sql += ",\n  last_pull = excluded.last_pull"
        }
        if lastPush != nil {
            sql += ",\n  last_push = excluded.last_push"
        }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw ExtensionError.updateFailed
        }
        defer { sqlite3_finalize(statement) }

        var bindIndex: Int32 = 1
        sqlite3_bind_text(statement, bindIndex, (sourceId as NSString).utf8String, -1, nil)
        bindIndex += 1

        if let lastPull = lastPull {
            sqlite3_bind_int64(statement, bindIndex, Int64(lastPull))
            bindIndex += 1
        }

        if let lastPush = lastPush {
            sqlite3_bind_int64(statement, bindIndex, Int64(lastPush))
        }

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw ExtensionError.updateFailed
        }
    }

    /// Get last pull timestamp for incremental sync
    func getLastPull() throws -> Int? {
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
            throw ExtensionError.cantOpen
        }
        defer {
            sqlite3_close(db)
        }

        let query = "SELECT last_pull FROM beadster_source WHERE id = '1'"

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            throw ExtensionError.queryFailed
        }
        defer { sqlite3_finalize(statement) }

        if sqlite3_step(statement) == SQLITE_ROW {
            if sqlite3_column_type(statement, 0) != SQLITE_NULL {
                return Int(sqlite3_column_int64(statement, 0))
            }
        }

        return nil
    }
}

// MARK: - Models

struct SyncInfo {
    let issueId: String
    let cloudId: String
    let syncedAt: Int
    let cloudUpdatedAt: Int?
    let localUpdatedAt: Int?
    let syncStatus: String
}

// MARK: - Errors

enum ExtensionError: Error {
    case cantOpen
    case createFailed
    case queryFailed
    case updateFailed
}
