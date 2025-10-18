//
//  SourceIDGenerator.swift
//  Beadster
//
//  Generates deterministic source IDs from project paths
//  Matches the approach in src/sync/Sources/CloudAPI.swift
//

import Foundation

class SourceIDGenerator {
    /// Generates a deterministic source ID from a file path
    /// Uses base64 encoding of the path (same as CLI)
    static func generate(from path: String) -> String {
        guard let data = path.data(using: .utf8) else {
            return ""
        }

        let base64 = data.base64EncodedString()
        return String(base64.prefix(16))
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
