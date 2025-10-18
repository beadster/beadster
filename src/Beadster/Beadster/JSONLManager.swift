//
//  JSONLManager.swift
//  Beadster
//
//  Created by Anton Podviaznikov on 10/18/25.
//

import Foundation

class JSONLManager {
    // Read issues from .beads/issues.jsonl
    static func readIssues(from url: URL) throws -> [Issue] {
        let issuesFile = url.appendingPathComponent(".beads/issues.jsonl")

        guard FileManager.default.fileExists(atPath: issuesFile.path) else {
            return []
        }

        let content = try String(contentsOf: issuesFile, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return try lines.compactMap { line in
            guard let data = line.data(using: .utf8) else { return nil }
            return try? decoder.decode(Issue.self, from: data)
        }
    }

    // Write issues to .beads/issues.jsonl
    static func writeIssues(_ issues: [Issue], to url: URL) throws {
        let beadsDir = url.appendingPathComponent(".beads")
        let issuesFile = beadsDir.appendingPathComponent("issues.jsonl")

        // create .beads directory if needed
        if !FileManager.default.fileExists(atPath: beadsDir.path) {
            try FileManager.default.createDirectory(at: beadsDir, withIntermediateDirectories: true)
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let lines = try issues.map { issue in
            let data = try encoder.encode(issue)
            return String(data: data, encoding: .utf8)!
        }

        let content = lines.joined(separator: "\n") + "\n"
        try content.write(to: issuesFile, atomically: true, encoding: .utf8)
    }
}
