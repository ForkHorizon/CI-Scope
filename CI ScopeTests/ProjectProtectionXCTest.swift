// Tests for the protection settings view model: load, register, save and hooks.
import Foundation
import XCTest

@testable import CI_Scope

@MainActor
final class ProjectProtectionXCTest: XCTestCase {
    private let reply = """
        {"config":{"schema":1,"repository":"ForkHorizon/Example","version":1,"observeOnly":false,\
        "lanes":{"code-rules":{"enabled":true,"params":{"maxFileLines":600,"maxFunctionLines":80,"maxNestingDepth":4,"maxParameters":5,"ignore":[],"forbidSuppressions":true}},\
        "agent-guard":{"enabled":true},"language":{"enabled":false,"adapters":[]},"tests":{"enabled":false,"command":""}},\
        "protectedFiles":["Cargo.toml"],"mergeGate":{"requireGreen":true,"deleteBranchAfterMerge":false},"updatedBy":"owner","updatedAt":1},"digest":"x"}
        """

    private func model(hooksPath: String = "") -> ProjectProtectionViewModel {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let model = ProjectProtectionViewModel()
        model.client = ProjectConfigClient(session: URLSession(configuration: configuration))
        model.readToken = { "read-token" }
        model.adminLogin = { _ in (user: "owner", password: "pw") }
        model.installer = GitHooksInstaller(
            gatesRoot: URL(fileURLWithPath: "/tmp/gates"), hooksDirectory: URL(fileURLWithPath: "/tmp/ci-hooks"),
            run: { command in
                command.hasPrefix("git config") ? ShellResult(exitCode: 0, output: hooksPath) : ShellResult(exitCode: 0, output: "")
            })
        return model
    }

    func testLoadShowsTheServerConfig() async {
        StubURLProtocol.handler = { [reply] _ in (200, Data(reply.utf8)) }
        let model = model()
        await model.load(repository: "ForkHorizon/Example")
        XCTAssertEqual(model.config?.version, 1)
        XCTAssertNil(model.message)
    }

    func testAnUnknownProjectIsShownAsUnregistered() async {
        StubURLProtocol.handler = { _ in (404, Data(#"{"error":"project_config_not_found"}"#.utf8)) }
        let model = model()
        await model.load(repository: "ForkHorizon/Example")
        XCTAssertNil(model.config)
        XCTAssertEqual(model.message, "ForkHorizon/Example is not registered with CI Scope yet.")
    }

    func testRegisterAsksForTouchIDAndStoresTheNewConfig() async {
        StubURLProtocol.handler = { [reply] request in
            request.httpMethod == "POST" ? (200, Data(reply.utf8)) : (404, Data(#"{"error":"project_config_not_found"}"#.utf8))
        }
        let model = model()
        var reasons: [String] = []
        model.adminLogin = { reason in
            reasons.append(reason)
            return (user: "owner", password: "pw")
        }
        await model.load(repository: "ForkHorizon/Example")
        await model.register()
        XCTAssertEqual(model.config?.repository, "ForkHorizon/Example")
        XCTAssertEqual(reasons, ["register ForkHorizon/Example with CI Scope"])
    }

    func testSaveSendsTheEditedConfigAndKeepsTheServerAnswer() async throws {
        StubURLProtocol.handler = { [reply] _ in (200, Data(reply.utf8)) }
        let model = model()
        await model.load(repository: "ForkHorizon/Example")
        model.config?.mergeGate.deleteBranchAfterMerge = true
        await model.save()
        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "PUT")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(StubURLProtocol.lastBody)) as? [String: Any])
        let sent = try XCTUnwrap(body["config"] as? [String: Any])
        XCTAssertEqual((sent["mergeGate"] as? [String: Bool])?["deleteBranchAfterMerge"], true)
    }

    func testAWeakeningTheServerRefusesIsExplained() async {
        StubURLProtocol.handler = { [reply] request in
            request.httpMethod != "GET" ? (403, Data(#"{"error":"owner_approval_required"}"#.utf8)) : (200, Data(reply.utf8))
        }
        let model = model()
        await model.load(repository: "ForkHorizon/Example")
        model.config?.lanes.agentGuard.enabled = false
        await model.save()
        XCTAssertTrue(model.message?.contains("needs the owner's approval") == true)
        XCTAssertEqual(model.config?.lanes.agentGuard.enabled, false, "the edit stays on screen so it can be reverted or retried")
    }

    func testHooksStateFollowsTheInstaller() async {
        let none = model()
        await none.refreshHooks()
        XCTAssertEqual(none.hooks, .notInstalled)
        let other = model(hooksPath: "/somewhere/else")
        await other.installHooks()
        XCTAssertEqual(other.hooks, .otherHooksPath("/somewhere/else"))
        XCTAssertNotNil(other.message)
    }
}
