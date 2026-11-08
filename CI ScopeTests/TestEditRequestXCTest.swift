// Tests for how a test-edit request (no pull request) reads in the Inbox.
import Foundation
import XCTest

@testable import CI_Scope

final class TestEditRequestXCTest: XCTestCase {
    private func decode(_ json: String) throws -> ChangeRequest {
        try JSONDecoder().decode(ChangeRequest.self, from: Data(json.utf8))
    }

    func testTestEditRequestHasItsOwnTitleAndReason() throws {
        let request = try decode("""
            {"id":5,"repository":"A/one","pullRequest":0,"headSha":"abc","kind":"tests","reason":"T7.1 removes the old enrollment",
             "status":"pending","createdAt":1,"items":[{"path":"tests/daemon.rs","kind":"modified","fingerprint":"f","previous":"p"}]}
            """)
        XCTAssertTrue(request.isTestEdit)
        XCTAssertEqual(request.title, "Test edit")
        XCTAssertEqual(request.reason, "T7.1 removes the old enrollment")
    }

    func testRequestsFromAnOlderServerKeepTheirPullRequestTitle() throws {
        let request = try decode(#"{"id":2,"repository":"B/two","pullRequest":7,"headSha":"abcdef1234","status":"pending","createdAt":2,"items":[]}"#)
        XCTAssertFalse(request.isTestEdit)
        XCTAssertEqual(request.title, "PR #7")
    }
}
