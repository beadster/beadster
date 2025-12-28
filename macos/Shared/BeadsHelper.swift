//
//  BeadsHelper.swift
//  Beadster
//
//  Helper functions for working with beads directories
//

import Foundation
import SQLite3

enum BeadsHelper {
    /// Find the actual .db file in a .beads directory
    /// bd CLI names the database after the project name (e.g., myproject.db)
    /// Returns the full path to the .db file, or nil if not found
    static func findDatabaseFile(in beadsDir: URL) -> URL? {
        let beadsDirPath = beadsDir.appendingPathComponent(".beads")

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: beadsDirPath,
            includingPropertiesForKeys: nil
        ) else {
            return nil
        }

        // Find first .db file
        return files.first { $0.pathExtension == "db" }
    }

    /// Find the database file path from a project directory (String path)
    static func findDatabasePath(in projectPath: String) -> String? {
        let projectURL = URL(fileURLWithPath: projectPath)
        guard let dbURL = findDatabaseFile(in: projectURL) else {
            return nil
        }
        return dbURL.path
    }

    /// Check if a directory has a beads database or issues.jsonl
    /// The .db file is a cache, issues.jsonl is the source of truth
    static func hasBeadsDatabase(at url: URL) -> Bool {
        let beadsDir = url.appendingPathComponent(".beads")

        // Check for .db file (cache) - preferred for fast queries
        if findDatabaseFile(in: url) != nil {
            return true
        }

        // Check for issues.jsonl (source of truth) - always works
        let jsonlPath = beadsDir.appendingPathComponent("issues.jsonl")
        return FileManager.default.fileExists(atPath: jsonlPath.path)
    }

    /// Get the project prefix from the database config
    static func getProjectPrefix(dbPath: String) -> String? {
        var db: OpaquePointer?
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_close(db) }

        let query = "SELECT value FROM config WHERE key = 'prefix'"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        if sqlite3_step(statement) == SQLITE_ROW {
            let cString = sqlite3_column_text(statement, 0)
            return String(cString: cString!)
        }

        return nil
    }
}
