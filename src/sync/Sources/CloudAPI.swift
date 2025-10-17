import Foundation

class CloudAPI {
    private let apiUrl: String
    private let apiKey: String

    init(apiUrl: String, apiKey: String) {
        self.apiUrl = apiUrl
        self.apiKey = apiKey
    }

    func pushIssues(source: Source, issues: [Issue]) async throws {
        let sourceId = generateSourceId(path: source.path)

        let payload: [String: Any] = [
            "source": [
                "id": sourceId,
                "name": source.name,
                "type": "local",
                "path": source.path
            ],
            "issues": issues.map { issue in
                var issueDict: [String: Any] = [
                    "id": "\(sourceId)_\(issue.beadsId)",
                    "beads_id": issue.beadsId,
                    "title": issue.title,
                    "status": issue.status,
                    "labels": issue.labels,
                    "created_at": issue.createdAt,
                    "updated_at": issue.updatedAt
                ]

                if let body = issue.body { issueDict["body"] = body }
                if let priority = issue.priority { issueDict["priority"] = priority }
                if let sessionId = issue.sessionId { issueDict["session_id"] = sessionId }
                if let client = issue.client { issueDict["client"] = client }
                if let projectName = issue.projectName { issueDict["project_name"] = projectName }

                return issueDict
            }
        ]

        let url = URL(string: "\(apiUrl)/api/sync/push")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.pushFailed
        }
    }

    func pullChanges(source: Source, since: Int) async throws -> [Issue] {
        let sourceId = generateSourceId(path: source.path)
        let urlString = "\(apiUrl)/api/sync/pull?source_id=\(sourceId)&since=\(since)"
        guard let url = URL(string: urlString) else {
            throw APIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.pullFailed
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let changes = try decoder.decode([Issue].self, from: data)

        return changes
    }

    private func generateSourceId(path: String) -> String {
        let data = path.data(using: .utf8)!
        let base64 = data.base64EncodedString()
        return String(base64.prefix(16))
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
