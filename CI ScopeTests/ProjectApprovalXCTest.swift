// Tests for the website Touch ID approval step of ProjectConfigClient.update.
import Foundation
import XCTest
@testable import CI_Scope

final class ProjectApprovalXCTest: XCTestCase {
    private let config =
        "{\"schema\":1,\"repository\":\"ForkHorizon/Example\",\"version\":1,\"observeOnly\":false,\"lanes\":{\"code-rules\":{\"enabled\":true,\"params\":{\"maxFileLines\":600,\"maxFunctionLines\":80,\"maxNestingDepth\":4,\"maxParameters\":5,\"ignore\":[],\"forbidSuppressions\":true}},\"agent-guard\":{\"enabled\":true},\"language\":{\"enabled\":false,\"adapters\":[]},\"tests\":{\"enabled\":false,\"command\":\"\"}},\"protectedFiles\":[\"Cargo.toml\"],\"mergeGate\":{\"requireGreen\":true,\"deleteBranchAfterMerge\":false},\"updatedBy\":\"owner\",\"updatedAt\":1700000000000}"

    private func client(open: @escaping (URL) -> Void) -> ProjectConfigClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        var client = ProjectConfigClient(session: URLSession(configuration: configuration))
        client.open = open
        client.pollInterval = .milliseconds(10)
        client.approvalTimeout = .milliseconds(200)
        return client
    }

    func testAWeakeningOpensTheApprovalPageWaitsForTouchIDAndRetriesWithTheApproval() async throws {
        nonisolated(unsafe) var putBodies: [[String: Any]] = []
        nonisolated(unsafe) var statuses = ["pending", "approved"]
        StubURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/approvals/request") {
                return (200, Data("{\"id\":\"abc\",\"path\":\"/api/ci/v2/approvals/page?id=abc\"}".utf8))
            }
            if path.hasSuffix("/approvals/status") { return (200, Data("{\"state\":\"\(statuses.removeFirst())\"}".utf8)) }
            let body = (try? JSONSerialization.jsonObject(with: StubURLProtocol.lastBody ?? Data()) as? [String: Any]) ?? [:]
            putBodies.append(body)
            if body["approval"] == nil { return (403, Data("{\"error\":\"owner_approval_required\"}".utf8)) }
            return (200, Data("{\"config\":\(self.config),\"digest\":\"x\"}".utf8))
        }
        nonisolated(unsafe) var opened: URL?
        let decoded = try JSONDecoder().decode(ProjectConfig.self, from: Data(config.utf8))
        _ = try await client { opened = $0 }.update(decoded, admin: (user: "owner", password: "pw"))
        XCTAssertEqual(opened?.absoluteString, "https://ci.forkhorizon.com/api/ci/v2/approvals/page?id=abc")
        XCTAssertEqual(putBodies.count, 2)
        XCTAssertEqual((putBodies.last?["approval"] as? [String: String])?["id"], "abc")
    }

    func testNoTouchIDInTimeLeavesTheConfigUnchanged() async throws {
        nonisolated(unsafe) var puts = 0
        StubURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/approvals/request") { return (200, Data("{\"id\":\"abc\",\"path\":\"/p?id=abc\"}".utf8)) }
            if path.hasSuffix("/approvals/status") { return (200, Data("{\"state\":\"pending\"}".utf8)) }
            puts += 1
            return (403, Data("{\"error\":\"owner_approval_required\"}".utf8))
        }
        let decoded = try JSONDecoder().decode(ProjectConfig.self, from: Data(config.utf8))
        do {
            _ = try await client { _ in }.update(decoded, admin: (user: "owner", password: "pw"))
            XCTFail("expected a timeout")
        } catch ProjectConfigError.approvalTimedOut {
            XCTAssertEqual(puts, 1)
        }
    }
}
