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
}
