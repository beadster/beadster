import Foundation
import SQLite3

/// Reads from beads.db (beads core tables)
/// Note: beads.db is rebuilt from JSONL by beads automatically
/// Path: .beads/beads.db
public class BeadsDatabase {
    private let dbPath: String
    private var db: OpaquePointer?

    // Init with String path (for CLI)
    public init(beadsDir: String) {
        self.dbPath = "\(beadsDir)/.beads/beads.db"
    }

    // Init with URL (for macOS app)
    public init(beadsDir: URL) {
        self.dbPath = beadsDir.appendingPathComponent(".beads/beads.db").path
    }

    public func open() throws {
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw DatabaseError.cantOpen
        }

        // set busy timeout to 5 seconds
        sqlite3_busy_timeout(db, 5000)
    }

    public func close() {
        sqlite3_close(db)
    }

    public func getAllIssues() throws -> [Issue] {
        // retry up to 3 times on database locked errors
        var lastError: Error?
        for attempt in 0..<3 {
            do {
                return try getAllIssuesInternal()
            } catch DatabaseError.locked {
                lastError = DatabaseError.locked
                if attempt < 2 {
                    print("⏳ Database locked, retry \(attempt + 1)/3...")
                    Thread.sleep(forTimeInterval: 0.5)
                }
            }
        }
        throw lastError ?? DatabaseError.queryFailed
    }

    private func getAllIssuesInternal() throws -> [Issue] {
        var issues: [Issue] = []

        // Get all issues with their labels from beads tables
        let query = """
        SELECT
            i.id,
            i.title,
            i.description,
            i.status,
            i.priority,
            i.issue_type,
            i.created_at,
            i.updated_at,
            GROUP_CONCAT(l.label, ',') as labels
        FROM issues i
        LEFT JOIN labels l ON i.id = l.issue_id
        GROUP BY i.id
        """

        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(db, query, -1, &statement, nil)
        guard prepareResult == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            print("❌ getAllIssues query failed: \(errorMessage) (code: \(prepareResult))")

            if prepareResult == SQLITE_BUSY || prepareResult == SQLITE_LOCKED {
                throw DatabaseError.locked
            }
            throw DatabaseError.queryFailed
        }

        defer { sqlite3_finalize(statement) }

        while sqlite3_step(statement) == SQLITE_ROW {
            let id = String(cString: sqlite3_column_text(statement, 0))
            let title = String(cString: sqlite3_column_text(statement, 1))
            let description = sqlite3_column_text(statement, 2).map { String(cString: $0) }
            let status = String(cString: sqlite3_column_text(statement, 3))
            let priority = Int(sqlite3_column_int(statement, 4))
            let issueType = String(cString: sqlite3_column_text(statement, 5))
            let createdAtStr = String(cString: sqlite3_column_text(statement, 6))
            let updatedAtStr = String(cString: sqlite3_column_text(statement, 7))
            let labelsStr = sqlite3_column_text(statement, 8).map { String(cString: $0) }

            let labels = labelsStr?.split(separator: ",").map(String.init) ?? []

            // Extract session metadata from labels (using -x- prefix for system labels)
            let sessionId = extractLabel(from: labels, prefix: "-x-session:")
            let client = extractLabel(from: labels, prefix: "-x-client:")
            let projectName = extractLabel(from: labels, prefix: "-x-project:")

            // Convert datetime strings to unix timestamps
            let createdAt = dateToTimestamp(createdAtStr)
            let updatedAt = dateToTimestamp(updatedAtStr)

            issues.append(Issue(
                id: id,
                title: title,
                body: description,
                status: status,
                priority: priority,
                labels: labels,
                createdAt: createdAt,
                updatedAt: updatedAt,
                sessionId: sessionId,
                client: client,
                projectName: projectName
            ))
        }

        return issues
    }

    public func getIssues(ids: [String]) throws -> [Issue] {
        guard !ids.isEmpty else { return [] }

        var issues: [Issue] = []

        // Build placeholders for IN clause
        let placeholders = ids.map { _ in "?" }.joined(separator: ",")

        let query = """
        SELECT
            i.id,
            i.title,
            i.description,
            i.status,
            i.priority,
            i.issue_type,
            i.created_at,
            i.updated_at,
            GROUP_CONCAT(l.label, ',') as labels
        FROM issues i
        LEFT JOIN labels l ON i.id = l.issue_id
        WHERE i.id IN (\(placeholders))
        GROUP BY i.id
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.queryFailed
        }

        defer { sqlite3_finalize(statement) }

        // Bind IDs
        for (index, id) in ids.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), (id as NSString).utf8String, -1, nil)
        }

        while sqlite3_step(statement) == SQLITE_ROW {
            let id = String(cString: sqlite3_column_text(statement, 0))
            let title = String(cString: sqlite3_column_text(statement, 1))
            let description = sqlite3_column_text(statement, 2).map { String(cString: $0) }
            let status = String(cString: sqlite3_column_text(statement, 3))
            let priority = Int(sqlite3_column_int(statement, 4))
            let issueType = String(cString: sqlite3_column_text(statement, 5))
            let createdAtStr = String(cString: sqlite3_column_text(statement, 6))
            let updatedAtStr = String(cString: sqlite3_column_text(statement, 7))
            let labelsStr = sqlite3_column_text(statement, 8).map { String(cString: $0) }

            let labels = labelsStr?.split(separator: ",").map(String.init) ?? []

            let sessionId = extractLabel(from: labels, prefix: "-x-session:")
            let client = extractLabel(from: labels, prefix: "-x-client:")
            let projectName = extractLabel(from: labels, prefix: "-x-project:")

            let createdAt = dateToTimestamp(createdAtStr)
            let updatedAt = dateToTimestamp(updatedAtStr)

            issues.append(Issue(
                id: id,
                title: title,
                body: description,
                status: status,
                priority: priority,
                labels: labels,
                createdAt: createdAt,
                updatedAt: updatedAt,
                sessionId: sessionId,
                client: client,
                projectName: projectName
            ))
        }

        return issues
    }

    public func issueExists(beadsId: String) throws -> Bool {
        let query = "SELECT COUNT(*) FROM issues WHERE id = ?"

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.queryFailed
        }

        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, (beadsId as NSString).utf8String, -1, nil)

        if sqlite3_step(statement) == SQLITE_ROW {
            let count = sqlite3_column_int(statement, 0)
            return count > 0
        }

        return false
    }

    private func extractLabel(from labels: [String], prefix: String) -> String? {
        return labels.first { $0.hasPrefix(prefix) }?
            .replacingOccurrences(of: prefix, with: "")
    }

    private func dateToTimestamp(_ dateStr: String) -> Int {
        // Go format: "2025-10-17 22:19:13.718092 +0200 CEST m=+0.008369668"
        let components = dateStr.components(separatedBy: " ")
        if components.count >= 3 {
            // Combine: "2025-10-17T22:19:13.718092+0200"
            let dateTimeStr = "\(components[0])T\(components[1])\(components[2])"

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds, .withTimeZone]
            if let date = formatter.date(from: dateTimeStr) {
                return Int(date.timeIntervalSince1970)
            }
        }

        // Fallback: try standard ISO8601
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: dateStr) {
            return Int(date.timeIntervalSince1970)
        }

        // Last fallback: return current time
        return Int(Date().timeIntervalSince1970)
    }
}
