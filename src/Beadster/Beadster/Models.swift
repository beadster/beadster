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
    var issueType: String? // "bug", "feature", "task", "epic"
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
        case id, title, status, priority, labels, assignee
        case description = "body"  // API/DB uses "body" not "description"
        case issueType = "issue_type"
        case design
        case acceptanceCriteria = "acceptance_criteria"
        case notes
        case dueAt = "due_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case closedAt = "closed_at"
    }

    // Regular initializer for creating issues manually
    init(id: String, title: String, description: String?, status: String, priority: Int, issueType: String? = nil, labels: [String]? = nil, assignee: String? = nil, design: String? = nil, acceptanceCriteria: String? = nil, notes: String? = nil, dueAt: Int? = nil, createdAt: Date, updatedAt: Date, closedAt: Date? = nil) {
        self.id = id
        self.title = title
        self.description = description
        self.status = status
        self.priority = priority
        self.issueType = issueType
        self.labels = labels
        self.assignee = assignee
        self.design = design
        self.acceptanceCriteria = acceptanceCriteria
        self.notes = notes
        self.dueAt = dueAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.closedAt = closedAt
    }

    // Custom decoder to handle priority as either Int or String
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        status = try container.decode(String.self, forKey: .status)

        // Handle priority as Int or String
        if let priorityInt = try? container.decode(Int.self, forKey: .priority) {
            priority = priorityInt
        } else if let priorityString = try? container.decode(String.self, forKey: .priority),
                  let priorityInt = Int(priorityString) {
            priority = priorityInt
        } else {
            priority = 1 // default
        }

        issueType = try container.decodeIfPresent(String.self, forKey: .issueType)
        labels = try container.decodeIfPresent([String].self, forKey: .labels)
        assignee = try container.decodeIfPresent(String.self, forKey: .assignee)
        design = try container.decodeIfPresent(String.self, forKey: .design)
        acceptanceCriteria = try container.decodeIfPresent(String.self, forKey: .acceptanceCriteria)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        dueAt = try container.decodeIfPresent(Int.self, forKey: .dueAt)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        closedAt = try container.decodeIfPresent(Date.self, forKey: .closedAt)
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
