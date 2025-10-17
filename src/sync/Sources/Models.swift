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
