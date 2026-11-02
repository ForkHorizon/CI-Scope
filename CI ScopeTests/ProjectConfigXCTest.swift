import Foundation
import XCTest
@testable import CI_Scope

/// Canned replies for ProjectConfigClient; one handler at a time, so the tests below run serially.
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var lastBody: Data?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lastRequest = request
        Self.lastBody = request.httpBody ?? request.httpBodyStream.map { stream in
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(buffer, count: count)
            }
            return data
        }
        let (status, body) = Self.handler?(request) ?? (500, Data())
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class ProjectConfigXCTest: XCTestCase {
    // Produced by CI-Scope-Web defaultProjectConfig, so a server-side format change breaks this test.
    private let serverConfig = ###"{"schema":1,"repository":"ForkHorizon/Example","version":1,"observeOnly":false,"lanes":{"code-rules":{"enabled":true,"params":{"maxFileLines":600,"maxFunctionLines":80,"maxNestingDepth":4,"maxParameters":5,"ignore":[],"forbidSuppressions":true}},"agent-guard":{"enabled":true},"language":{"enabled":false,"adapters":[]},"tests":{"enabled":false,"command":""}},"protectedFiles":["Cargo.toml","**/Cargo.toml","clippy.toml","rustfmt.toml","deny.toml","rust-toolchain.toml","tsconfig.json",".eslintrc*","eslint.config.*","package.json","ruff.toml",".ruff.toml","pyproject.toml",".swiftlint.yml",".swift-format",".golangci.yml",".github/**"],"mergeGate":{"requireGreen":true,"deleteBranchAfterMerge":false},"updatedBy":"owner","updatedAt":1700000000000}"###

    private func client() -> ProjectConfigClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return ProjectConfigClient(session: URLSession(configuration: configuration), now: { Date(timeIntervalSince1970: 1_700_000_000) })
    }

    private func reply(_ config: String) -> Data { Data(#"{"config":\#(config),"digest":"x"}"#.utf8) }

    func testDecodesTheServerDefaultConfig() throws {
        let config = try JSONDecoder().decode(ProjectConfig.self, from: Data(serverConfig.utf8))
        XCTAssertEqual(config.repository, "ForkHorizon/Example")
        XCTAssertTrue(config.lanes.codeRules.enabled)
        XCTAssertEqual(config.lanes.codeRules.params.maxFileLines, 600)
        XCTAssertTrue(config.lanes.codeRules.params.forbidSuppressions)
        XCTAssertFalse(config.lanes.language.enabled)
        XCTAssertTrue(config.protectedFiles.contains("Cargo.toml"))
        XCTAssertTrue(config.mergeGate.requireGreen)
        XCTAssertEqual(config.summary, "code rules · agent guard")
    }

    func testEncodingKeepsTheServerLaneNames() throws {
        let config = try JSONDecoder().decode(ProjectConfig.self, from: Data(serverConfig.utf8))
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as? [String: Any]
        let lanes = try XCTUnwrap(object?["lanes"] as? [String: Any])
        XCTAssertEqual(Set(lanes.keys), ["code-rules", "agent-guard", "language", "tests"])
    }

    func testSummaryMentionsLanguagesTestsAndObserveOnly() throws {
        var config = try JSONDecoder().decode(ProjectConfig.self, from: Data(serverConfig.utf8))
        config.lanes.language = .init(enabled: true, adapters: ["rust", "swift"])
        config.lanes.tests = .init(enabled: true, command: "cargo test")
        config.observeOnly = true
        XCTAssertEqual(config.summary, "code rules · agent guard · rust, swift · tests (observe only)")
        config.lanes.codeRules.enabled = false
        config.lanes.agentGuard.enabled = false
        config.lanes.language.enabled = false
        config.lanes.tests.enabled = false
        XCTAssertEqual(config.summary, "no checks (observe only)")
    }

    func testReadSendsTheReadTokenAndTheRepository() async throws {
        StubURLProtocol.handler = { [self] _ in (200, reply(serverConfig)) }
        let config = try await client().read(repository: "ForkHorizon/Example", readToken: "read-token")
        XCTAssertEqual(config.version, 1)
        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-ci-scope-config-token"), "read-token")
        XCTAssertNil(request.value(forHTTPHeaderField: "authorization"))
        XCTAssertEqual(request.url?.query, "repository=ForkHorizon/Example")
        XCTAssertEqual(request.httpMethod ?? "GET", "GET")
    }

    func testUpdateSendsAdminLoginTheConfigAndATouchIDClaim() async throws {
        StubURLProtocol.handler = { [self] _ in (200, reply(serverConfig)) }
        let config = try JSONDecoder().decode(ProjectConfig.self, from: Data(serverConfig.utf8))
        _ = try await client().update(config, admin: (user: "owner", password: "pw"))
        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.value(forHTTPHeaderField: "authorization"), "Basic " + Data("owner:pw".utf8).base64EncodedString())
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(StubURLProtocol.lastBody)) as? [String: Any])
        let approval = try XCTUnwrap(body["approval"] as? [String: Any])
        XCTAssertEqual(approval["method"] as? String, "touch-id")
        XCTAssertEqual(approval["approvedAt"] as? Int, 1_700_000_000_000)
        XCTAssertEqual((body["config"] as? [String: Any])?["repository"] as? String, "ForkHorizon/Example")
    }

    func testServerRefusalsBecomeReadableErrors() async throws {
        StubURLProtocol.handler = { _ in (403, Data(#"{"error":"owner_approval_required"}"#.utf8)) }
        let config = try JSONDecoder().decode(ProjectConfig.self, from: Data(serverConfig.utf8))
        do {
            _ = try await client().update(config, admin: (user: "owner", password: "pw"))
            XCTFail("expected a refusal")
        } catch let error as ProjectConfigError {
            XCTAssertTrue(error.localizedDescription.contains("needs the owner's approval"))
            XCTAssertTrue(error.localizedDescription.contains("HTTP 403"))
        }
    }

    func testAMalformedReplyIsReported() async throws {
        StubURLProtocol.handler = { _ in (200, Data(#"{"config":{"schema":1}}"#.utf8)) }
        do {
            _ = try await client().read(repository: "ForkHorizon/Example", readToken: "t")
            XCTFail("expected a decoding failure")
        } catch ProjectConfigError.malformedResponse {
        }
    }
}
