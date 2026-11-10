// Tests for decoding the website Inbox and grouping pending change requests.
import Foundation
import XCTest

@testable import CI_Scope

@MainActor
final class ChangeRequestXCTest: XCTestCase {
    private let reply = Data(
        """
        {"changes":[
          {"id":2,"repository":"B/two","pullRequest":7,"headSha":"abcdef1234","status":"pending","createdAt":20,
           "items":[{"path":"scripts/check","kind":"modified","fingerprint":"f1","previous":"f0"}]},
          {"id":1,"repository":"A/one","pullRequest":null,"headSha":"1234567890","status":"approved","createdAt":10,"items":[]},
          {"id":3,"repository":"A/one","pullRequest":9,"headSha":"deadbeef00","status":"pending","createdAt":30,
           "items":[{"path":"Cargo.lock","kind":"added","fingerprint":"f2"}]}
        ]}
        """.utf8)

    func testDecodesAndGroupsPendingAcrossProjects() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        StubURLProtocol.handler = { _ in (200, self.reply) }
        let monitor = ChangeRequestMonitor()
        monitor.client = ChangeRequestsClient(session: URLSession(configuration: configuration))
        monitor.readToken = { "read-token" }
        await monitor.refresh()
        XCTAssertEqual(StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "x-ci-scope-config-token"), "read-token")
        XCTAssertNil(StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "authorization"), "listing sends no admin login")
        XCTAssertEqual(monitor.requests.count, 3)
        XCTAssertEqual(monitor.pending.count, 2)
        XCTAssertEqual(monitor.pendingByRepository.map(\.repository), ["A/one", "B/two"])
        XCTAssertNil(monitor.requests[2].items[0].previous)
        XCTAssertNil(monitor.requests[1].pullRequest)
    }

    func testAFailedRefreshKeepsTheListButMarksItOutOfDate() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        StubURLProtocol.handler = { _ in (200, self.reply) }
        let monitor = ChangeRequestMonitor()
        monitor.client = ChangeRequestsClient(session: URLSession(configuration: configuration))
        monitor.readToken = { "read-token" }
        await monitor.refresh()
        XCTAssertFalse(monitor.isStale)
        monitor.readToken = { throw ServerAuthorizerError.sshBlocked("host:22") }
        await monitor.refresh()
        XCTAssertTrue(monitor.isStale, "the website may have decided the requests since")
        XCTAssertEqual(monitor.pending.count, 2)
        monitor.readToken = { "read-token" }
        await monitor.refresh()
        XCTAssertFalse(monitor.isStale)
    }
}
