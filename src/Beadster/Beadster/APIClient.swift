//
//  APIClient.swift
//  Beadster
//
//  Created by Anton Podviaznikov on 10/18/25.
//

import Foundation

class APIClient {
    static let shared = APIClient()

    // POC: hardcoded dev API token
    private let apiToken = "dev-token-placeholder"
    private let baseURL = "https://beadster-dev-app.systemoperator.workers.dev"

    private init() {}

    // MARK: - Sources

    func getSources() async throws -> [Source] {
        let url = URL(string: "\(baseURL)/api/sources")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(SourcesResponse.self, from: data)
        return response.sources
    }

    // MARK: - Issues

    func getIssues(sourceId: String) async throws -> [Issue] {
        let url = URL(string: "\(baseURL)/api/sources/\(sourceId)/issues")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(IssuesResponse.self, from: data)
        return response.issues
    }

    func syncIssues(sourceId: String, issues: [Issue]) async throws -> SyncResponse {
        let url = URL(string: "\(baseURL)/api/sources/\(sourceId)/sync")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["issues": issues]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(SyncResponse.self, from: data)
    }

    // MARK: - Source Registration

    func registerSource(source: SourcePayload, issues: [Issue]) async throws -> String {
        let url = URL(string: "\(baseURL)/api/sync/push")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase

        let body: [String: Any] = [
            "source": try encoder.encode(source),
            "issues": try encoder.encode(issues)
        ]

        // Manually encode the JSON since we have mixed types
        var jsonObject: [String: Any] = [:]
        jsonObject["source"] = try JSONSerialization.jsonObject(with: try encoder.encode(source))
        jsonObject["issues"] = try JSONSerialization.jsonObject(with: try encoder.encode(issues))

        request.httpBody = try JSONSerialization.data(withJSONObject: jsonObject)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.registrationFailed
        }

        return source.id
    }
}

// MARK: - Source Payload

struct SourcePayload: Codable {
    let id: String
    let name: String
    let type: String
    let path: String
}

enum APIError: Error {
    case registrationFailed
}
