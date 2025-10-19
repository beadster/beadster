import Foundation
import SQLite3

class BeadsDatabase {
    private let dbPath: String
    private var db: OpaquePointer?

    init(beadsDir: String) {
        guard let foundPath = BeadsHelper.findDatabasePath(in: beadsDir) else {
            fatalError("No beads database found in \(beadsDir)")
        }
        self.dbPath = foundPath
    }

    func open() throws {
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw DatabaseError.cantOpen
        }
    }

    func close() {
        sqlite3_close(db)
    }

    func getAllIssues() throws -> [Issue] {
        var issues: [Issue] = []

        // Get all issues with their labels
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
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
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
            let createdAt = String(cString: sqlite3_column_text(statement, 6))
            let updatedAt = String(cString: sqlite3_column_text(statement, 7))
            let labelsStr = sqlite3_column_text(statement, 8).map { String(cString: $0) }

            let labels = labelsStr?.split(separator: ",").map(String.init) ?? []

            // Extract session metadata from labels (using -x- prefix for system labels)
            let sessionId = extractLabel(from: labels, prefix: "-x-session:")
            let client = extractLabel(from: labels, prefix: "-x-client:")
            let projectName = extractLabel(from: labels, prefix: "-x-project:")

            // Convert datetime strings to unix timestamps
            let createdAtTimestamp = dateToTimestamp(createdAt) ?? 0
            let updatedAtTimestamp = dateToTimestamp(updatedAt) ?? 0

            issues.append(Issue(
                id: id,
                beadsId: id,
                title: title,
                body: description,
                status: status,
                priority: String(priority),
                labels: labels,
                createdAt: createdAtTimestamp,
                updatedAt: updatedAtTimestamp,
                sessionId: sessionId,
                client: client,
                projectName: projectName
            ))
        }

        return issues
    }

    func issueExists(beadsId: String) throws -> Bool {
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

    private func dateToTimestamp(_ dateStr: String) -> Int? {
        // Go format: "2025-10-17 22:19:13.718092 +0200 CEST m=+0.008369668"
        // We need to extract just the date/time part before the timezone
        let components = dateStr.components(separatedBy: " ")
        if components.count >= 3 {
            // Combine date and time: "2025-10-17 22:19:13.718092"
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

        return nil
    }
}
