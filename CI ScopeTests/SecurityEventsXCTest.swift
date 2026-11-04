// Tests for fetching, announcing and acknowledging security events.
import Foundation
import XCTest

@testable import CI_Scope

@MainActor
final class SecurityEventsXCTest: XCTestCase {
    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private let eventsReply = Data(
        """
        {"events":[
          {"id":1,"repository":"ForkHorizon/Example","kind":"protected_files_changed","detail":"PR #5 modified Cargo.toml","createdAt":10},
          {"id":2,"repository":"ForkHorizon/Example","kind":"config_weakening_refused","detail":"agent tried","createdAt":20}
        ]}
        """.utf8)

    private func monitor(notified: @escaping (SecurityEvent) -> Void = { _ in }) -> SecurityEventMonitor {
        let monitor = SecurityEventMonitor()
        monitor.client = SecurityEventsClient(session: session())
        monitor.readToken = { "read-token" }
        monitor.adminLogin = { _ in (user: "owner", password: "pw") }
        monitor.notify = notified
        return monitor
    }

    func testTitlesNameTheKind() {
        let event = SecurityEvent(id: 1, repository: "a/b", kind: "protected_files_changed", detail: "", createdAt: 0)
        XCTAssertEqual(event.title, "Protected files were changed")
        XCTAssertEqual(SecurityEvent(id: 2, repository: "a/b", kind: "unknown", detail: "", createdAt: 0).title, "Security event")
    }

    func testRefreshFetchesWithTheReadTokenAndNotifiesEachEventOnce() async throws {
        StubURLProtocol.handler = { [eventsReply] _ in (200, eventsReply) }
        var announced: [Int] = []
        let monitor = monitor { announced.append($0.id) }
        await monitor.refresh()
        await monitor.refresh()
        XCTAssertEqual(monitor.events.map(\.id), [1, 2])
        XCTAssertEqual(announced, [1, 2], "a second refresh must not announce the same events again")
        XCTAssertEqual(StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "x-ci-scope-config-token"), "read-token")
        XCTAssertNil(monitor.message)
    }

    func testAnAnswerWithBadEventsIsReported() async {
        StubURLProtocol.handler = { _ in (200, Data(#"{"events":[{"id":"x"}]}"#.utf8)) }
        let monitor = monitor()
        await monitor.refresh()
        XCTAssertTrue(monitor.events.isEmpty)
        XCTAssertNotNil(monitor.message)
    }

    func testAcknowledgeSendsTheIdsWithTheAdminLoginAndClearsTheList() async throws {
        StubURLProtocol.handler = { [eventsReply] request in
            request.httpMethod == "POST" ? (200, Data(#"{"acknowledged":2}"#.utf8)) : (200, eventsReply)
        }
        let monitor = monitor()
        await monitor.refresh()
        await monitor.acknowledgeAll()
        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.path, "/api/ci/v2/events/ack")
        XCTAssertEqual(request.value(forHTTPHeaderField: "authorization"), "Basic " + Data("owner:pw".utf8).base64EncodedString())
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(StubURLProtocol.lastBody)) as? [String: [Int]])
        XCTAssertEqual(body, ["ids": [1, 2]])
        XCTAssertTrue(monitor.events.isEmpty)
    }

    func testACancelledTouchIDLeavesTheEventsInPlace() async {
        StubURLProtocol.handler = { [eventsReply] _ in (200, eventsReply) }
        let monitor = monitor()
        monitor.adminLogin = { _ in throw PolicyAuthorizerError.cancelled }
        await monitor.refresh()
        await monitor.acknowledgeAll()
        XCTAssertEqual(monitor.events.count, 2)
        XCTAssertEqual(monitor.message, PolicyAuthorizerError.cancelled.localizedDescription)
    }
}
