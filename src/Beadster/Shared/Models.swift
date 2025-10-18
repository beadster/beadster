import Foundation

// MARK: - Config (CLI)

public struct Config: Codable {
    public let apiKey: String
    public let apiUrl: String
    public let sources: [SourceConfig]
}

public struct SourceConfig: Codable {
    public let name: String
    public let path: String
}

// MARK: - Source (Project)

public struct Source: Identifiable, Codable, Hashable {
    public let id: String
    public let name: String
    public let type: String // "local-git", "local-no-git", "virtual"
    public let path: String?
    public var lastSync: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, type, path
        case lastSync = "last_sync"
    }
}

// Payload for API requests
public struct SourcePayload: Codable {
    public let id: String
    public let name: String
    public let type: String
    public let path: String?
}

// MARK: - Issue

public struct Issue: Identifiable, Codable, Hashable {
    public let id: String
    public var title: String
    public var body: String? // using "body" for API compatibility
    public var status: String // "open", "in_progress", "blocked", "closed"
    public var priority: Int // 0-4
    public var issueType: String? // "bug", "feature", "task", "epic"
    public var labels: [String]
    public var assignee: String?

    public var design: String?
    public var acceptanceCriteria: String?
    public var notes: String?

    public var createdAt: Int // unix timestamp
    public var updatedAt: Int // unix timestamp
    public var closedAt: Int?

    // Session metadata (from labels)
    public var sessionId: String?
    public var client: String?
    public var projectName: String?

    // For sync compatibility
    public var beadsId: String { id } // local beads ID (bd-1, bd-2)

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

    public init(id: String, title: String, body: String?, status: String, priority: Int,
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

    public init(from decoder: Decoder) throws {
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

public struct Dependency: Codable, Hashable {
    public let issueId: String
    public let dependsOnId: String
    public let type: String // "blocks", "related", "parent-child", "discovered-from"

    enum CodingKeys: String, CodingKey {
        case issueId = "issue_id"
        case dependsOnId = "depends_on_id"
        case type
    }
}

// MARK: - API Response Types

public struct SyncResponse: Codable {
    public let synced: Int
    public let syncLogId: String?

    enum CodingKeys: String, CodingKey {
        case synced
        case syncLogId = "sync_log_id"
    }
}

public struct SourcesResponse: Codable {
    public let sources: [Source]
}

public struct IssuesResponse: Codable {
    public let issues: [Issue]
}

// MARK: - Errors

public enum DatabaseError: Error {
    case cantOpen
    case queryFailed
    case updateFailed
    case locked
}

public enum APIError: Error {
    case pushFailed
    case pullFailed
    case invalidResponse
    case networkError
    case registrationFailed
    case syncFailed
    case deviceRegistrationFailed
    case trackingFailed
    case unauthorized
}
