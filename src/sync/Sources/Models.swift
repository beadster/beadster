import Foundation

struct Config: Codable {
    let apiKey: String
    let apiUrl: String
    let sources: [Source]
}

struct Source: Codable {
    let name: String
    let path: String
}

struct Issue: Codable {
    let id: String
    let beadsId: String
    let title: String
    let body: String?
    let status: String
    let priority: String?
    let labels: [String]
    let createdAt: Int
    let updatedAt: Int

    // Session metadata
    let sessionId: String?
    let client: String?
    let projectName: String?

    enum CodingKeys: String, CodingKey {
        case id, title, body, status, priority, labels
        case beadsId = "beads_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case sessionId = "session_id"
        case client
        case projectName = "project_name"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        beadsId = try container.decodeIfPresent(String.self, forKey: .beadsId) ?? id
        title = try container.decode(String.self, forKey: .title)
        body = try container.decodeIfPresent(String.self, forKey: .body)
        status = try container.decode(String.self, forKey: .status)
        priority = try container.decodeIfPresent(String.self, forKey: .priority)
        createdAt = try container.decodeIfPresent(Int.self, forKey: .createdAt) ?? Int(Date().timeIntervalSince1970)
        updatedAt = try container.decodeIfPresent(Int.self, forKey: .updatedAt) ?? Int(Date().timeIntervalSince1970)
        sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId)
        client = try container.decodeIfPresent(String.self, forKey: .client)
        projectName = try container.decodeIfPresent(String.self, forKey: .projectName)

        // Labels can be either a string (JSON) or an array
        if let labelsString = try? container.decode(String.self, forKey: .labels) {
            // Parse JSON string to array
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

    init(id: String, beadsId: String, title: String, body: String?, status: String,
         priority: String?, labels: [String], createdAt: Int, updatedAt: Int,
         sessionId: String?, client: String?, projectName: String?) {
        self.id = id
        self.beadsId = beadsId
        self.title = title
        self.body = body
        self.status = status
        self.priority = priority
        self.labels = labels
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sessionId = sessionId
        self.client = client
        self.projectName = projectName
    }
}

enum DatabaseError: Error {
    case cantOpen
    case queryFailed
    case updateFailed
}

enum APIError: Error {
    case pushFailed
    case pullFailed
    case invalidResponse
}
