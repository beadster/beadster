import Foundation

// MARK: - Config (CLI)

struct Config: Codable {
    let apiKey: String
    let apiUrl: String
    let sources: [SourceConfig]
}

struct SourceConfig: Codable {
    let name: String
    let path: String
}

// MARK: - Source (Project)

struct Source: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let type: String // "local-git", "local-no-git", "virtual"
    let path: String?
    var lastSync: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, type, path
        case lastSync = "last_sync"
    }
}

// Payload for API requests
struct SourcePayload: Codable {
    let id: String
    let name: String
    let type: String
    let path: String?
}

// MARK: - Issue

struct Issue: Identifiable, Codable, Hashable {
    let id: String
    var title: String
    var body: String? // using "body" for API compatibility
    var status: String // "open", "in_progress", "blocked", "closed"
    var priority: Int // 0-4
    var issueType: String? // "bug", "feature", "task", "epic"
    var labels: [String]
    var assignee: String?

    var design: String?
    var acceptanceCriteria: String?
    var notes: String?

    var createdAt: Int // unix timestamp
    var updatedAt: Int // unix timestamp
    var closedAt: Int?

    // Session metadata (from labels)
    var sessionId: String?
    var client: String?
    var projectName: String?

    // For sync compatibility
    var beadsId: String { id } // local beads ID (bd-1, bd-2)

    enum CodingKeys: String, CodingKey {
        case id, title, status, priority, labels, assignee
        case body
        case issueType = "issue_type"
        case design
        case acceptanceCriteria = "acceptance_criteria"
        case notes
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case closedAt = "closed_at"
        case sessionId = "session_id"
        case client
        case projectName = "project_name"
    }

    init(id: String, title: String, body: String?, status: String, priority: Int,
         issueType: String? = nil, labels: [String] = [], assignee: String? = nil,
         design: String? = nil, acceptanceCriteria: String? = nil, notes: String? = nil,
         createdAt: Int, updatedAt: Int, closedAt: Int? = nil,
         sessionId: String? = nil, client: String? = nil, projectName: String? = nil) {
        self.id = id
        self.title = title
        self.body = body
        self.status = status
        self.priority = priority
        self.issueType = issueType
        self.labels = labels
        self.assignee = assignee
        self.design = design
        self.acceptanceCriteria = acceptanceCriteria
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.closedAt = closedAt
        self.sessionId = sessionId
        self.client = client
        self.projectName = projectName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        body = try container.decodeIfPresent(String.self, forKey: .body)
        status = try container.decode(String.self, forKey: .status)

        // Handle priority as Int or String
        if let priorityInt = try? container.decode(Int.self, forKey: .priority) {
            priority = priorityInt
        } else if let priorityString = try? container.decode(String.self, forKey: .priority),
                  let priorityInt = Int(priorityString) {
            priority = priorityInt
        } else {
            priority = 2 // default
        }

        issueType = try container.decodeIfPresent(String.self, forKey: .issueType)
        assignee = try container.decodeIfPresent(String.self, forKey: .assignee)
        design = try container.decodeIfPresent(String.self, forKey: .design)
        acceptanceCriteria = try container.decodeIfPresent(String.self, forKey: .acceptanceCriteria)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)

        // Handle timestamps (from cloud they're Int, need to ensure)
        createdAt = try container.decodeIfPresent(Int.self, forKey: .createdAt) ?? Int(Date().timeIntervalSince1970)
        updatedAt = try container.decodeIfPresent(Int.self, forKey: .updatedAt) ?? Int(Date().timeIntervalSince1970)
        closedAt = try container.decodeIfPresent(Int.self, forKey: .closedAt)

        // Session metadata
        sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId)
        client = try container.decodeIfPresent(String.self, forKey: .client)
        projectName = try container.decodeIfPresent(String.self, forKey: .projectName)

        // Labels can be JSON string or array
        if let labelsString = try? container.decode(String.self, forKey: .labels) {
            // Parse JSON string
            if let data = labelsString.data(using: .utf8),
               let array = try? JSONDecoder().decode([String].self, from: data) {
                labels = array
            } else {
                labels = []
            }
        } else if let labelsArray = try? container.decode([String].self, forKey: .labels) {
            labels = labelsArray
        } else {
            labels = []
        }
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
    let synced: Int
    let syncLogId: String?

    enum CodingKeys: String, CodingKey {
        case synced
        case syncLogId = "sync_log_id"
    }
}

struct SourcesResponse: Codable {
    let sources: [Source]
}

struct IssuesResponse: Codable {
    let issues: [Issue]
}

// MARK: - Errors

enum DatabaseError: Error {
    case cantOpen
    case queryFailed
    case updateFailed
}

enum APIError: Error {
    case pushFailed
    case pullFailed
    case invalidResponse
    case networkError
}
