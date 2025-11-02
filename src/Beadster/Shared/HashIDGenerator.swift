import Foundation
import CommonCrypto

/// Configuration for adaptive ID length
public struct AdaptiveIDConfig {
    let maxCollisionProbability: Double
    let minLength: Int
    let maxLength: Int

    public static func defaultConfig() -> AdaptiveIDConfig {
        return AdaptiveIDConfig(
            maxCollisionProbability: 0.25,  // 25% threshold
            minLength: 4,
            maxLength: 8
        )
    }
}

/// Hash-based ID generator matching beads v0.20.1+ implementation
/// Port of Go code from github.com/steveyegge/beads/internal/storage/sqlite
public class HashIDGenerator {

    /// Generate a hash-based issue ID
    /// Exact port of generateHashID from beads Go code
    ///
    /// - Parameters:
    ///   - prefix: Issue prefix (e.g., "beadster")
    ///   - title: Issue title
    ///   - description: Issue description (optional)
    ///   - creator: Creator identifier
    ///   - timestamp: Creation timestamp
    ///   - length: Hash length (4-8 characters)
    ///   - nonce: Collision resolution nonce
    /// - Returns: Hash ID in format "prefix-hash"
    public static func generateHashID(
        prefix: String,
        title: String,
        description: String?,
        creator: String,
        timestamp: Date,
        length: Int,
        nonce: Int
    ) -> String {
        // Combine inputs into a stable content string
        // Include nonce to handle hash collisions
        let desc = description ?? ""
        let timestampNano = Int64(timestamp.timeIntervalSince1970 * 1_000_000_000)
        let content = "\(title)|\(desc)|\(creator)|\(timestampNano)|\(nonce)"

        // Hash the content using SHA256
        guard let data = content.data(using: .utf8) else {
            return "\(prefix)-error"
        }

        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { bufferPtr in
            guard let baseAddress = bufferPtr.baseAddress else { return }
            CC_SHA256(baseAddress, CC_LONG(data.count), &hash)
        }

        // Use variable length (4-8 hex chars)
        let shortHash: String
        switch length {
        case 4:
            // 2 bytes → 4 hex chars
            shortHash = hash[..<2].map { String(format: "%02x", $0) }.joined()
        case 5:
            // 3 bytes → 6 chars, take 5
            let hexStr = hash[..<3].map { String(format: "%02x", $0) }.joined()
            shortHash = String(hexStr.prefix(5))
        case 6:
            // 3 bytes → 6 hex chars
            shortHash = hash[..<3].map { String(format: "%02x", $0) }.joined()
        case 7:
            // 4 bytes → 8 chars, take 7
            let hexStr = hash[..<4].map { String(format: "%02x", $0) }.joined()
            shortHash = String(hexStr.prefix(7))
        case 8:
            // 4 bytes → 8 hex chars
            shortHash = hash[..<4].map { String(format: "%02x", $0) }.joined()
        default:
            // default to 6
            shortHash = hash[..<3].map { String(format: "%02x", $0) }.joined()
        }

        return "\(prefix)-\(shortHash)"
    }

    /// Calculate collision probability using birthday paradox approximation
    /// P(collision) ≈ 1 - e^(-n²/2N) where N = 36^idLength
    ///
    /// Note: Original Go code uses base 36 (alphanumeric), but actual implementation
    /// uses hex (base 16). We use base 16 here to match actual behavior.
    ///
    /// - Parameters:
    ///   - numIssues: Number of existing issues
    ///   - idLength: Length of hash ID
    /// - Returns: Collision probability (0.0 to 1.0)
    public static func collisionProbability(numIssues: Int, idLength: Int) -> Double {
        let base = 16.0  // Hexadecimal encoding
        let totalPossibilities = pow(base, Double(idLength))
        let n = Double(numIssues)
        let exponent = -(n * n) / (2.0 * totalPossibilities)
        return 1.0 - exp(exponent)
    }

    /// Compute adaptive ID length based on issue count and configuration
    /// Exact port of computeAdaptiveLength from beads Go code
    ///
    /// - Parameters:
    ///   - numIssues: Number of existing issues
    ///   - config: Adaptive ID configuration
    /// - Returns: Recommended hash length (4-8)
    public static func computeAdaptiveLength(numIssues: Int, config: AdaptiveIDConfig) -> Int {
        for length in config.minLength...config.maxLength {
            let prob = collisionProbability(numIssues: numIssues, idLength: length)
            if prob <= config.maxCollisionProbability {
                return length
            }
        }
        return config.maxLength
    }

    /// Get adaptive ID length based on existing issues
    ///
    /// - Parameters:
    ///   - prefix: Issue prefix
    ///   - existingIssues: List of existing issues
    /// - Returns: Recommended hash length
    public static func getAdaptiveIDLength(prefix: String, existingIssues: [Issue]) -> Int {
        let numIssues = countTopLevelIssues(prefix: prefix, existingIssues: existingIssues)
        let config = AdaptiveIDConfig.defaultConfig()
        return computeAdaptiveLength(numIssues: numIssues, config: config)
    }

    /// Count top-level issues (excluding children with dots)
    /// Exact port of countTopLevelIssues from beads Go code
    ///
    /// - Parameters:
    ///   - prefix: Issue prefix
    ///   - existingIssues: List of existing issues
    /// - Returns: Count of top-level issues
    public static func countTopLevelIssues(prefix: String, existingIssues: [Issue]) -> Int {
        let prefixPattern = "\(prefix)-"
        return existingIssues.filter { issue in
            // Check if ID starts with prefix-
            guard issue.id.hasPrefix(prefixPattern) else { return false }

            // Extract the part after prefix-
            let afterPrefix = String(issue.id.dropFirst(prefixPattern.count))

            // Exclude child issues (those containing dots)
            return !afterPrefix.contains(".")
        }.count
    }

    /// Generate a new unique hash-based issue ID with collision detection
    /// Exact port of CreateIssue ID generation logic from beads Go code
    ///
    /// - Parameters:
    ///   - prefix: Issue prefix
    ///   - title: Issue title
    ///   - description: Issue description (optional)
    ///   - creator: Creator identifier
    ///   - timestamp: Creation timestamp
    ///   - existingIssues: List of existing issues to check for collisions
    /// - Returns: Generated unique ID
    public static func generateUniqueID(
        prefix: String,
        title: String,
        description: String?,
        creator: String,
        timestamp: Date,
        existingIssues: [Issue]
    ) -> String {
        let baseLength = getAdaptiveIDLength(prefix: prefix, existingIssues: existingIssues)
        let maxLength = 8

        // Build set of existing IDs for fast collision detection
        let existingIDs = Set(existingIssues.map { $0.id })

        // Try lengths from base to max
        for length in baseLength...maxLength {
            // Try up to 10 nonces per length
            for nonce in 0..<10 {
                let candidate = generateHashID(
                    prefix: prefix,
                    title: title,
                    description: description,
                    creator: creator,
                    timestamp: timestamp,
                    length: length,
                    nonce: nonce
                )

                // Check for collision
                if !existingIDs.contains(candidate) {
                    return candidate
                }
            }
        }

        // Fallback: if we exhausted all nonces and lengths, use UUID
        // This should be extremely rare
        print("WARNING: Hash ID generation exhausted all nonces, falling back to UUID")
        return "\(prefix)-\(UUID().uuidString.prefix(8))"
    }
}
