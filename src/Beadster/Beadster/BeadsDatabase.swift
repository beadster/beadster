//
//  BeadsDatabase.swift
//  Beadster
//
//  Created by Anton Podviaznikov on 10/18/25.
//

import Foundation
import SQLite3

class BeadsDatabase {
    private let dbPath: String
    private var db: OpaquePointer?

    init(beadsDir: URL) {
        self.dbPath = beadsDir.appendingPathComponent(".beads/beadster.db").path
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

            let labelsList = labelsStr?.split(separator: ",").map(String.init)

            // Convert datetime strings to Date objects
            let createdAtDate = parseDate(createdAt)
            let updatedAtDate = parseDate(updatedAt)

            issues.append(Issue(
                id: id,
                title: title,
                description: description,
                status: status,
                priority: priority,
                issueType: issueType,
                labels: labelsList,
                createdAt: createdAtDate,
                updatedAt: updatedAtDate,
                closedAt: nil
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

    private func parseDate(_ dateStr: String) -> Date {
        // Go format: "2025-10-17 22:19:13.718092 +0200 CEST m=+0.008369668"
        // We need to extract just the date/time part before the timezone
        let components = dateStr.components(separatedBy: " ")
        if components.count >= 3 {
            // Combine date and time with timezone: "2025-10-17T22:19:13.718092+0200"
            let dateTimeStr = "\(components[0])T\(components[1])\(components[2])"

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds, .withTimeZone]
            if let date = formatter.date(from: dateTimeStr) {
                return date
            }
        }

        // Fallback: try standard ISO8601
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: dateStr) {
            return date
        }

        // Last fallback: return epoch
        return Date(timeIntervalSince1970: 0)
    }
}

enum DatabaseError: Error {
    case cantOpen
    case queryFailed
}
