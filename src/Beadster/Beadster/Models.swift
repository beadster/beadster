//
//  Models.swift
//  Beadster
//
//  Created by Anton Podviaznikov on 10/18/25.
//

import Foundation

// MARK: - Source (Project)

struct Source: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let type: String // "local-git", "local-no-git"
    let path: String?
    var lastSync: Date?
    var bookmark: Data? // security bookmark for sandbox access

    enum CodingKeys: String, CodingKey {
        case id, name, type, path
        case lastSync = "last_sync"
    }
}

// MARK: - Issue

struct Issue: Identifiable, Codable, Hashable {
    let id: String
    var title: String
    var description: String?
    var status: String // "open", "in_progress", "blocked", "closed"
    var priority: Int // 0-4
    var issueType: String // "bug", "feature", "task", "epic"
    var labels: [String]?
    var assignee: String?

    var design: String?
    var acceptanceCriteria: String?
    var notes: String?

    var dueAt: Int?
    var createdAt: Date
    var updatedAt: Date
    var closedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, title, description, status, priority, labels, assignee
        case issueType = "issue_type"
        case design
        case acceptanceCriteria = "acceptance_criteria"
        case notes
        case dueAt = "due_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case closedAt = "closed_at"
    }
}

// MARK: - Dependency

struct Dependency: Codable, Hashable {
    let issueId: String
    let dependsOnId: String
    let type: String // "blocks", "related", "parent-child", "discovered-from"

    enum CodingKeys: String, CodingKey {
        case issueId = "issue_id"
        case dependsOnId = "depends_on_id"
        case type
    }
}

// MARK: - API Response Types

struct SyncResponse: Codable {
    let created: Int
    let updated: Int
    let skipped: Int
}

struct SourcesResponse: Codable {
    let sources: [Source]
}

struct IssuesResponse: Codable {
    let issues: [Issue]
}
