//
//  APIClient.swift
//  Beadster
//
//  Created by Anton Podviaznikov on 10/18/25.
//

import Foundation

class APIClient {
    static let shared = APIClient()

    // POC: hardcoded dev API token (from D1: anton@beadster.dev)
    private let apiToken = "C9F2A5A2-5E3E-41BF-8C9A-436B55AB5A8A"
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

        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ registerSource: Invalid response type")
            throw APIError.registrationFailed
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let responseBody = String(data: data, encoding: .utf8) ?? "Unable to decode response"
            print("❌ registerSource failed: HTTP \(httpResponse.statusCode)")
            print("   Response: \(responseBody)")
            throw APIError.registrationFailed
        }

        print("✅ registerSource: HTTP \(httpResponse.statusCode)")
        return source.id
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
    case deviceRegistrationFailed
    case trackingFailed
}
