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

    // Git repository info
    public var gitRepoUrl: String?
    public var gitCurrentBranch: String?

    enum CodingKeys: String, CodingKey {
        case id, name, type, path
        case lastSync = "last_sync"
        case gitRepoUrl = "git_repo_url"
        case gitCurrentBranch = "git_current_branch"
    }
}

// Payload for API requests
public struct SourcePayload: Codable {
    public let id: String
    public let name: String
    public let type: String
    public let path: String?
    public let gitRepoUrl: String?
    public let gitCurrentBranch: String?

    enum CodingKeys: String, CodingKey {
        case id, name, type, path
        case gitRepoUrl = "git_repo_url"
        case gitCurrentBranch = "git_current_branch"
    }

    public init(id: String, name: String, type: String, path: String?, gitRepoUrl: String? = nil, gitCurrentBranch: String? = nil) {
        self.id = id
        self.name = name
        self.type = type
        self.path = path
        self.gitRepoUrl = gitRepoUrl
        self.gitCurrentBranch = gitCurrentBranch
    }
}

// MARK: - Issue Enums

public enum IssueStatus: String, Codable, CaseIterable {
    case open = "open"
    case inProgress = "in_progress"
    case blocked = "blocked"
    case closed = "closed"

    public var displayName: String {
        switch self {
        case .open: return "Open"
        case .inProgress: return "In Progress"
        case .blocked: return "Blocked"
        case .closed: return "Closed"
        }
    }
}

public enum IssuePriority: Int, Codable, CaseIterable {
    case p0 = 0
    case p1 = 1
    case p2 = 2
    case p3 = 3
    case p4 = 4

    public var displayName: String {
        return "P\(rawValue)"
    }

    public var description: String {
        switch self {
        case .p0: return "P0 - Critical"
        case .p1: return "P1 - Urgent"
        case .p2: return "P2 - Medium"
        case .p3: return "P3 - Lower"
        case .p4: return "P4 - Lowest"
        }
    }
}

public enum IssueType: String, Codable, CaseIterable {
    case bug = "bug"
    case feature = "feature"
    case task = "task"
    case epic = "epic"
    case chore = "chore"

    public var displayName: String {
        return rawValue.capitalized
    }
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

    // Git context (captured when issue created)
    public var gitRepoUrl: String?
    public var gitBranch: String?
    public var gitCommitHash: String?
    public var gitIsDirty: Bool?

    // External reference (for hybrid workflows with Jira, GitHub, Linear, etc.)
    public var externalRef: String?

    // Time estimation
    public var estimatedMinutes: Int?

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
        case gitRepoUrl = "git_repo_url"
        case gitBranch = "git_branch"
        case gitCommitHash = "git_commit_hash"
        case gitIsDirty = "git_is_dirty"
        case externalRef = "external_ref"
        case estimatedMinutes = "estimated_minutes"
    }

    public init(id: String, title: String, body: String?, status: String, priority: Int,
         issueType: String? = nil, labels: [String] = [], assignee: String? = nil,
         design: String? = nil, acceptanceCriteria: String? = nil, notes: String? = nil,
         createdAt: Int, updatedAt: Int, closedAt: Int? = nil,
         sessionId: String? = nil, client: String? = nil, projectName: String? = nil,
         gitRepoUrl: String? = nil, gitBranch: String? = nil, gitCommitHash: String? = nil, gitIsDirty: Bool? = nil,
         externalRef: String? = nil, estimatedMinutes: Int? = nil) {
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
        self.gitRepoUrl = gitRepoUrl
        self.gitBranch = gitBranch
        self.gitCommitHash = gitCommitHash
        self.gitIsDirty = gitIsDirty
        self.externalRef = externalRef
        self.estimatedMinutes = estimatedMinutes
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

        // Handle timestamps - can be Int (unix timestamp) or String (ISO 8601)
        createdAt = Self.decodeTimestamp(from: container, forKey: .createdAt) ?? Int(Date().timeIntervalSince1970)
        updatedAt = Self.decodeTimestamp(from: container, forKey: .updatedAt) ?? Int(Date().timeIntervalSince1970)
        closedAt = Self.decodeTimestamp(from: container, forKey: .closedAt)

        // Session metadata
        sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId)
        client = try container.decodeIfPresent(String.self, forKey: .client)
        projectName = try container.decodeIfPresent(String.self, forKey: .projectName)

        // Git context
        gitRepoUrl = try container.decodeIfPresent(String.self, forKey: .gitRepoUrl)
        gitBranch = try container.decodeIfPresent(String.self, forKey: .gitBranch)
        gitCommitHash = try container.decodeIfPresent(String.self, forKey: .gitCommitHash)

        // Handle gitIsDirty as Int or Bool
        if let isDirtyInt = try? container.decode(Int.self, forKey: .gitIsDirty) {
            gitIsDirty = isDirtyInt != 0
        } else if let isDirtyBool = try? container.decode(Bool.self, forKey: .gitIsDirty) {
            gitIsDirty = isDirtyBool
        } else {
            gitIsDirty = nil
        }

        // External reference
        externalRef = try container.decodeIfPresent(String.self, forKey: .externalRef)

        // Time estimation
        estimatedMinutes = try container.decodeIfPresent(Int.self, forKey: .estimatedMinutes)

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

    // Helper to decode timestamp from either Int or ISO 8601 String
    private static func decodeTimestamp(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> Int? {
        // Try Int first (unix timestamp)
        if let timestamp = try? container.decode(Int.self, forKey: key) {
            return timestamp
        }

        // Try String (ISO 8601)
        if let dateString = try? container.decode(String.self, forKey: key) {
            if let timestamp = DateUtils.parseISO8601(from: dateString) {
                return timestamp
            } else {
                print("Issue: Failed to parse ISO8601 date string for field '\(key.stringValue)': \(dateString)")
                print("  String length: \(dateString.count), has Z: \(dateString.hasSuffix("Z")), has +: \(dateString.contains("+"))")
            }
        }

        return nil
    }

    // Custom encoding - ALWAYS write timestamps as ISO 8601 strings for JSONL compatibility
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(body, forKey: .body)
        try container.encode(status, forKey: .status)
        try container.encode(priority, forKey: .priority)
        try container.encodeIfPresent(issueType, forKey: .issueType)
        try container.encode(labels, forKey: .labels)
        try container.encodeIfPresent(assignee, forKey: .assignee)
        try container.encodeIfPresent(design, forKey: .design)
        try container.encodeIfPresent(acceptanceCriteria, forKey: .acceptanceCriteria)
        try container.encodeIfPresent(notes, forKey: .notes)

        // Encode timestamps as ISO 8601 strings
        try container.encode(DateUtils.formatISO8601(from: createdAt), forKey: .createdAt)
        try container.encode(DateUtils.formatISO8601(from: updatedAt), forKey: .updatedAt)
        if let closedAt = closedAt {
            try container.encode(DateUtils.formatISO8601(from: closedAt), forKey: .closedAt)
        }

        try container.encodeIfPresent(sessionId, forKey: .sessionId)
        try container.encodeIfPresent(client, forKey: .client)
        try container.encodeIfPresent(projectName, forKey: .projectName)
        try container.encodeIfPresent(gitRepoUrl, forKey: .gitRepoUrl)
        try container.encodeIfPresent(gitBranch, forKey: .gitBranch)
        try container.encodeIfPresent(gitCommitHash, forKey: .gitCommitHash)
        try container.encodeIfPresent(gitIsDirty, forKey: .gitIsDirty)
        try container.encodeIfPresent(externalRef, forKey: .externalRef)
        try container.encodeIfPresent(estimatedMinutes, forKey: .estimatedMinutes)
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

// MARK: - Dependencies

public struct IssueDependency: Codable, Hashable {
    public let issueId: String
    public let dependsOnId: String
    public let type: String

    enum CodingKeys: String, CodingKey {
        case issueId = "issue_id"
        case dependsOnId = "depends_on_id"
        case type
    }

    public init(issueId: String, dependsOnId: String, type: String = "blocks") {
        self.issueId = issueId
        self.dependsOnId = dependsOnId
        self.type = type
    }
}

// MARK: - Errors

public enum DatabaseError: Error {
    case cantOpen
    case queryFailed
    case updateFailed
    case locked
}

public enum APIError: Error {
    case notAuthenticated
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
