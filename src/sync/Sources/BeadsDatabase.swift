import Foundation
import SQLite3

class BeadsDatabase {
    private let dbPath: String
    private var db: OpaquePointer?

    init(beadsDir: String) {
        self.dbPath = "\(beadsDir)/.beads/beads.db"
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

        let query = """
        SELECT id, title, body, status, priority, labels, created_at, updated_at
        FROM issues
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.queryFailed
        }

        defer { sqlite3_finalize(statement) }

        while sqlite3_step(statement) == SQLITE_ROW {
            let id = String(cString: sqlite3_column_text(statement, 0))
            let title = String(cString: sqlite3_column_text(statement, 1))
            let body = sqlite3_column_text(statement, 2).map { String(cString: $0) }
            let status = String(cString: sqlite3_column_text(statement, 3))
            let priority = sqlite3_column_text(statement, 4).map { String(cString: $0) }
            let labelsJSON = sqlite3_column_text(statement, 5).map { String(cString: $0) } ?? "[]"
            let createdAt = Int(sqlite3_column_int64(statement, 6))
            let updatedAt = Int(sqlite3_column_int64(statement, 7))

            let labels = (try? JSONDecoder().decode([String].self, from: labelsJSON.data(using: .utf8)!)) ?? []

            // Extract session metadata from labels
            let sessionId = extractLabel(from: labels, prefix: "session:")
            let client = extractLabel(from: labels, prefix: "client:")
            let projectName = extractLabel(from: labels, prefix: "project:")

            issues.append(Issue(
                id: id,
                beadsId: id,
                title: title,
                body: body,
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

    private func extractLabel(from labels: [String], prefix: String) -> String? {
        return labels.first { $0.hasPrefix(prefix) }?
            .replacingOccurrences(of: prefix, with: "")
    }
}
