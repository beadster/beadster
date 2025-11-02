import XCTest
@testable import Shared

final class HashIDGeneratorTests: XCTestCase {

    // MARK: - Basic Hash Generation Tests

    func testGenerateHashID_Length4() {
        let id = HashIDGenerator.generateHashID(
            prefix: "test",
            title: "Sample Issue",
            description: "Description",
            creator: "user1",
            timestamp: Date(timeIntervalSince1970: 1234567890),
            length: 4,
            nonce: 0
        )

        XCTAssertTrue(id.hasPrefix("test-"), "ID should start with prefix")
        let hash = String(id.dropFirst(5)) // "test-" is 5 chars
        XCTAssertEqual(hash.count, 4, "Hash should be 4 characters")
        XCTAssertTrue(isHexString(hash), "Hash should be hexadecimal")
    }

    func testGenerateHashID_Length5() {
        let id = HashIDGenerator.generateHashID(
            prefix: "test",
            title: "Sample Issue",
            description: "Description",
            creator: "user1",
            timestamp: Date(timeIntervalSince1970: 1234567890),
            length: 5,
            nonce: 0
        )

        let hash = String(id.dropFirst(5))
        XCTAssertEqual(hash.count, 5, "Hash should be 5 characters")
        XCTAssertTrue(isHexString(hash), "Hash should be hexadecimal")
    }

    func testGenerateHashID_Length6() {
        let id = HashIDGenerator.generateHashID(
            prefix: "test",
            title: "Sample Issue",
            description: "Description",
            creator: "user1",
            timestamp: Date(timeIntervalSince1970: 1234567890),
            length: 6,
            nonce: 0
        )

        let hash = String(id.dropFirst(5))
        XCTAssertEqual(hash.count, 6, "Hash should be 6 characters")
        XCTAssertTrue(isHexString(hash), "Hash should be hexadecimal")
    }

    func testGenerateHashID_Length7() {
        let id = HashIDGenerator.generateHashID(
            prefix: "test",
            title: "Sample Issue",
            description: "Description",
            creator: "user1",
            timestamp: Date(timeIntervalSince1970: 1234567890),
            length: 7,
            nonce: 0
        )

        let hash = String(id.dropFirst(5))
        XCTAssertEqual(hash.count, 7, "Hash should be 7 characters")
        XCTAssertTrue(isHexString(hash), "Hash should be hexadecimal")
    }

    func testGenerateHashID_Length8() {
        let id = HashIDGenerator.generateHashID(
            prefix: "test",
            title: "Sample Issue",
            description: "Description",
            creator: "user1",
            timestamp: Date(timeIntervalSince1970: 1234567890),
            length: 8,
            nonce: 0
        )

        let hash = String(id.dropFirst(5))
        XCTAssertEqual(hash.count, 8, "Hash should be 8 characters")
        XCTAssertTrue(isHexString(hash), "Hash should be hexadecimal")
    }

    // MARK: - Determinism Tests

    func testGenerateHashID_Deterministic() {
        let timestamp = Date(timeIntervalSince1970: 1234567890)

        let id1 = HashIDGenerator.generateHashID(
            prefix: "test",
            title: "Sample Issue",
            description: "Description",
            creator: "user1",
            timestamp: timestamp,
            length: 6,
            nonce: 0
        )

        let id2 = HashIDGenerator.generateHashID(
            prefix: "test",
            title: "Sample Issue",
            description: "Description",
            creator: "user1",
            timestamp: timestamp,
            length: 6,
            nonce: 0
        )

        XCTAssertEqual(id1, id2, "Same inputs should produce same hash")
    }

    func testGenerateHashID_DifferentNonceProducesDifferentHash() {
        let timestamp = Date(timeIntervalSince1970: 1234567890)

        let id1 = HashIDGenerator.generateHashID(
            prefix: "test",
            title: "Sample Issue",
            description: "Description",
            creator: "user1",
            timestamp: timestamp,
            length: 6,
            nonce: 0
        )

        let id2 = HashIDGenerator.generateHashID(
            prefix: "test",
            title: "Sample Issue",
            description: "Description",
            creator: "user1",
            timestamp: timestamp,
            length: 6,
            nonce: 1
        )

        XCTAssertNotEqual(id1, id2, "Different nonces should produce different hashes")
    }

    func testGenerateHashID_DifferentTitleProducesDifferentHash() {
        let timestamp = Date(timeIntervalSince1970: 1234567890)

        let id1 = HashIDGenerator.generateHashID(
            prefix: "test",
            title: "Issue A",
            description: "Description",
            creator: "user1",
            timestamp: timestamp,
            length: 6,
            nonce: 0
        )

        let id2 = HashIDGenerator.generateHashID(
            prefix: "test",
            title: "Issue B",
            description: "Description",
            creator: "user1",
            timestamp: timestamp,
            length: 6,
            nonce: 0
        )

        XCTAssertNotEqual(id1, id2, "Different titles should produce different hashes")
    }

    // MARK: - Collision Probability Tests

    func testCollisionProbability_SmallDatabase() {
        // With 100 issues and 4-char hash (16^4 = 65,536 possibilities)
        let prob = HashIDGenerator.collisionProbability(numIssues: 100, idLength: 4)
        // Probability should be relatively low
        XCTAssertLessThan(prob, 0.1, "Collision probability should be < 10% for 100 issues with 4-char hash")
    }

    func testCollisionProbability_LargeDatabase() {
        // With 1000 issues and 4-char hash (16^4 = 65,536 possibilities)
        let prob = HashIDGenerator.collisionProbability(numIssues: 1000, idLength: 4)
        // Probability should be higher
        XCTAssertGreaterThan(prob, 0.05, "Collision probability should increase with more issues")
    }

    func testCollisionProbability_IncreasesWithMoreIssues() {
        let prob100 = HashIDGenerator.collisionProbability(numIssues: 100, idLength: 4)
        let prob500 = HashIDGenerator.collisionProbability(numIssues: 500, idLength: 4)

        XCTAssertGreaterThan(prob500, prob100, "More issues should increase collision probability")
    }

    func testCollisionProbability_DecreasesWithLongerHash() {
        let prob4 = HashIDGenerator.collisionProbability(numIssues: 500, idLength: 4)
        let prob6 = HashIDGenerator.collisionProbability(numIssues: 500, idLength: 6)

        XCTAssertLessThan(prob6, prob4, "Longer hashes should decrease collision probability")
    }

    // MARK: - Adaptive Length Tests

    func testComputeAdaptiveLength_SmallDatabase() {
        let config = AdaptiveIDConfig.defaultConfig()
        let length = HashIDGenerator.computeAdaptiveLength(numIssues: 100, config: config)
        XCTAssertEqual(length, 4, "Should use minimum length for small database")
    }

    func testComputeAdaptiveLength_MediumDatabase() {
        let config = AdaptiveIDConfig.defaultConfig()
        let length = HashIDGenerator.computeAdaptiveLength(numIssues: 500, config: config)
        XCTAssertGreaterThanOrEqual(length, 5, "Should use longer length for medium database")
    }

    func testComputeAdaptiveLength_LargeDatabase() {
        let config = AdaptiveIDConfig.defaultConfig()
        let length = HashIDGenerator.computeAdaptiveLength(numIssues: 2000, config: config)
        XCTAssertGreaterThanOrEqual(length, 6, "Should use longer length for large database")
    }

    func testComputeAdaptiveLength_RespectsMaxLength() {
        let config = AdaptiveIDConfig.defaultConfig()
        let length = HashIDGenerator.computeAdaptiveLength(numIssues: 1_000_000, config: config)
        XCTAssertLessThanOrEqual(length, config.maxLength, "Should not exceed max length")
    }

    // MARK: - Count Top-Level Issues Tests

    func testCountTopLevelIssues_ExcludesChildren() {
        let issues = [
            createIssue(id: "test-a1b2"),
            createIssue(id: "test-c3d4"),
            createIssue(id: "test-a1b2.1"),  // child
            createIssue(id: "test-a1b2.2"),  // child
            createIssue(id: "test-c3d4.1"),  // child
        ]

        let count = HashIDGenerator.countTopLevelIssues(prefix: "test", existingIssues: issues)
        XCTAssertEqual(count, 2, "Should count only top-level issues")
    }

    func testCountTopLevelIssues_ExcludesOtherPrefixes() {
        let issues = [
            createIssue(id: "test-a1b2"),
            createIssue(id: "test-c3d4"),
            createIssue(id: "other-e5f6"),
            createIssue(id: "another-g7h8"),
        ]

        let count = HashIDGenerator.countTopLevelIssues(prefix: "test", existingIssues: issues)
        XCTAssertEqual(count, 2, "Should count only issues with matching prefix")
    }

    func testCountTopLevelIssues_EmptyList() {
        let issues: [Issue] = []
        let count = HashIDGenerator.countTopLevelIssues(prefix: "test", existingIssues: issues)
        XCTAssertEqual(count, 0, "Should return 0 for empty list")
    }

    // MARK: - Unique ID Generation Tests

    func testGenerateUniqueID_NoCollisions() {
        let existingIssues = [
            createIssue(id: "test-a1b2"),
            createIssue(id: "test-c3d4"),
        ]

        let id = HashIDGenerator.generateUniqueID(
            prefix: "test",
            title: "New Issue",
            description: "Description",
            creator: "user1",
            timestamp: Date(),
            existingIssues: existingIssues
        )

        XCTAssertTrue(id.hasPrefix("test-"), "Should have correct prefix")
        XCTAssertFalse(existingIssues.contains { $0.id == id }, "Should not collide with existing IDs")
    }

    func testGenerateUniqueID_HandlesCollisions() {
        // Create a scenario where first nonce might collide
        var existingIssues: [Issue] = []
        for i in 0..<100 {
            existingIssues.append(createIssue(id: "test-\(String(format: "%04x", i))"))
        }

        let id = HashIDGenerator.generateUniqueID(
            prefix: "test",
            title: "New Issue",
            description: "Description",
            creator: "user1",
            timestamp: Date(),
            existingIssues: existingIssues
        )

        XCTAssertTrue(id.hasPrefix("test-"), "Should have correct prefix")
        XCTAssertFalse(existingIssues.contains { $0.id == id }, "Should generate unique ID even with many existing")
    }

    func testGenerateUniqueID_DifferentTimestampsProduceDifferentIDs() {
        let existingIssues: [Issue] = []

        let id1 = HashIDGenerator.generateUniqueID(
            prefix: "test",
            title: "Issue",
            description: "Description",
            creator: "user1",
            timestamp: Date(timeIntervalSince1970: 1234567890),
            existingIssues: existingIssues
        )

        let id2 = HashIDGenerator.generateUniqueID(
            prefix: "test",
            title: "Issue",
            description: "Description",
            creator: "user1",
            timestamp: Date(timeIntervalSince1970: 1234567891),
            existingIssues: existingIssues
        )

        XCTAssertNotEqual(id1, id2, "Different timestamps should produce different IDs")
    }

    // MARK: - Helper Functions

    private func isHexString(_ str: String) -> Bool {
        let hexCharacterSet = CharacterSet(charactersIn: "0123456789abcdef")
        return str.unicodeScalars.allSatisfy { hexCharacterSet.contains($0) }
    }

    private func createIssue(id: String) -> Issue {
        return Issue(
            id: id,
            title: "Test Issue",
            body: nil,
            status: "open",
            priority: 2,
            issueType: nil,
            labels: [],
            assignee: nil,
            design: nil,
            acceptanceCriteria: nil,
            notes: nil,
            createdAt: Int(Date().timeIntervalSince1970),
            updatedAt: Int(Date().timeIntervalSince1970),
            closedAt: nil,
            sessionId: nil,
            client: nil,
            projectName: nil
        )
    }
}
