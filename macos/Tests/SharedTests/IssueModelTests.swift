import XCTest
@testable import Shared

final class IssueModelTests: XCTestCase {
    func testDecodesBeadsDescriptionIntoBody() throws {
        let data = Data("""
        {"id":"ProjectJournal-x6o","title":"Index saves unnecessarily","description":"Index is being saved unnecessarily.","status":"open","priority":2,"type":"bug","labels":["indexing"],"created_at":"2026-07-31T12:33:46Z","updated_at":"2026-07-31T12:33:46Z"}
        """.utf8)

        let issue = try JSONDecoder().decode(Issue.self, from: data)

        XCTAssertEqual(issue.body, "Index is being saved unnecessarily.")
        XCTAssertEqual(issue.issueType, "bug")
    }

    func testBodyTakesPrecedenceOverDescription() throws {
        let data = Data("""
        {"id":"test-1","title":"Body wins","body":"Body text","description":"Description text","status":"open","priority":2,"issue_type":"task","labels":[],"created_at":"2026-07-31T12:33:46Z","updated_at":"2026-07-31T12:33:46Z"}
        """.utf8)

        let issue = try JSONDecoder().decode(Issue.self, from: data)

        XCTAssertEqual(issue.body, "Body text")
        XCTAssertEqual(issue.issueType, "task")
    }
}
