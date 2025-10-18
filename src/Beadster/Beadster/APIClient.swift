//
//  APIClient.swift
//  Beadster
//
//  Created by Anton Podviaznikov on 10/18/25.
//

import Foundation

class APIClient {
    static let shared = APIClient()

    // POC: hardcoded dev API token (from remote D1: anton@systemoperator.com)
    private let apiToken = "3ae6ab7b-3e95-49b5-8d96-5ab6e8102373"
    private let baseURL = "https://beadster-dev-api.systemoperator.workers.dev"

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

    // MARK: - Pull Changes

    func pullChanges(sourceId: String, since: Int) async throws -> [Issue] {
        let urlString = "\(baseURL)/api/sync/pull?source_id=\(sourceId)&since=\(since)"
        guard let url = URL(string: urlString) else {
            throw APIError.syncFailed
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: request)
        let decoder = JSONDecoder()
        // Don't use convertFromSnakeCase - Issue model CodingKeys already handle snake_case mapping
        decoder.dateDecodingStrategy = .secondsSince1970
        let issues = try decoder.decode([Issue].self, from: data)
        return issues
    }

    // MARK: - Push Issues

    func pushIssues(source: SourcePayload, issues: [Issue]) async throws {
        let url = URL(string: "\(baseURL)/api/sync/push")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Transform issues to match API format (add beads_id, format id)
        let transformedIssues = issues.map { issue -> [String: Any] in
            var dict: [String: Any] = [
                "id": "\(source.id)_\(issue.id)",  // format: sourceId_beadsId
                "beads_id": issue.id,              // beadster-1, beadster-2, etc
                "title": issue.title,
                "status": issue.status,
                "labels": issue.labels ?? [],
                "created_at": Int(issue.createdAt.timeIntervalSince1970),
                "updated_at": Int(issue.updatedAt.timeIntervalSince1970)
            ]

            // Add optional fields only if they exist
            if let description = issue.description { dict["body"] = description }
            if issue.priority > 0 { dict["priority"] = issue.priority }

            return dict
        }

        let requestBody: [String: Any] = [
            "source": [
                "id": source.id,
                "name": source.name,
                "type": source.type,
                "path": source.path
            ],
            "issues": transformedIssues
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ pushIssues: Invalid response type")
            throw APIError.syncFailed
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let responseBody = String(data: data, encoding: .utf8) ?? "Unable to decode response"
            print("❌ pushIssues failed: HTTP \(httpResponse.statusCode)")
            print("   Response: \(responseBody)")
            throw APIError.syncFailed
        }

        print("✅ pushIssues: HTTP \(httpResponse.statusCode)")
    }

    // MARK: - Device Registration

    func registerDevice(deviceId: String, hardwareUUID: String, deviceName: String, deviceType: String, platform: String, platformVersion: String) async throws {
        let url = URL(string: "\(baseURL)/api/devices/register")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "device_id": deviceId,
            "hardware_uuid": hardwareUUID,
            "device_name": deviceName,
            "device_type": deviceType,
            "platform": platform,
            "platform_version": platformVersion
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.deviceRegistrationFailed
        }
    }

    // MARK: - Device Tracking

    func recordDeviceTracking(issueId: String, deviceId: String, client: String) async throws {
        let url = URL(string: "\(baseURL)/api/device-tracking/record")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "issue_id": issueId,
            "device_id": deviceId,
            "client": client
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.trackingFailed
        }
    }

    func getDeviceTracking(issueId: String) async throws -> [DeviceTracking] {
        let url = URL(string: "\(baseURL)/api/device-tracking/\(issueId)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(DeviceTrackingResponse.self, from: data)
        return response.tracking
    }
}

// MARK: - Source Payload

struct SourcePayload: Codable {
    let id: String
    let name: String
    let type: String
    let path: String
}

// MARK: - Device Tracking Models

struct DeviceTracking: Codable {
    let issueId: String
    let deviceId: String
    let client: String
    let firstSeen: Int
    let lastSeen: Int
    let deviceName: String?
    let deviceType: String?
    let platform: String?
}

struct DeviceTrackingResponse: Codable {
    let tracking: [DeviceTracking]
}

enum APIError: Error {
    case registrationFailed
    case syncFailed
    case deviceRegistrationFailed
    case trackingFailed
}
