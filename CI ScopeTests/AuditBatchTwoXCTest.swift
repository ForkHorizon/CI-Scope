// Tests for event paging and the hooks installer's checkout checks.
import Foundation
import XCTest
@testable import CI_Scope

final class AuditBatchTwoXCTest: XCTestCase {
    private func events(_ range: ClosedRange<Int>) -> Data {
        let items = range.map {
            "{\"id\":\($0),\"repository\":\"ForkHorizon/Example\",\"kind\":\"protected_files_changed\",\"detail\":\"d\",\"createdAt\":1}"
        }
        return Data("{\"events\":[\(items.joined(separator: ","))]}".utf8)
    }

    func testFetchOpenFollowsThePagesUntilTheLastShortOne() async throws {
        nonisolated(unsafe) var afters: [String] = []
        StubURLProtocol.handler = { request in
            let after =
                URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "after" }?.value ?? ""
            afters.append(after)
            return (200, after == "0" ? self.events(1...50) : self.events(51...53))
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let client = SecurityEventsClient(session: URLSession(configuration: configuration))
        let all = try await client.fetchOpen(readToken: "t")
        XCTAssertEqual(all.count, 53)
        XCTAssertEqual(afters, ["0", "50"])
    }

    private func installer(head: String, status: String, sha: String?, clean: Bool, record: @escaping (String) -> Void = { _ in })
        -> GitHooksInstaller
    {
        GitHooksInstaller(
            gatesRoot: URL(fileURLWithPath: "/tmp/gates"), hooksDirectory: URL(fileURLWithPath: "/tmp/hooks"),
            expectedGatesSHA: sha, requireCleanCheckout: clean,
            run: { command in
                record(command)
                if command.hasPrefix("git config") { return ShellResult(exitCode: 0, output: "") }
                if command.contains("rev-parse") { return ShellResult(exitCode: 0, output: head + "\n") }
                if command.contains("status") { return ShellResult(exitCode: 0, output: status) }
                return ShellResult(exitCode: 0, output: "ok")
            })
    }

    func testInstallRefusesAnUnpinnedCheckout() async {
        do {
            try await installer(head: "bbbbbbbb", status: "", sha: "aaaaaaaa", clean: false).install()
            XCTFail("expected a refusal")
        } catch let error as GitHooksInstaller.InstallError {
            XCTAssertTrue(error.localizedDescription.contains("pinned"))
        } catch { XCTFail("\(error)") }
    }

    func testInstallRefusesLocalEditsInTheGatesCheckout() async {
        var commands: [String] = []
        do {
            try await installer(head: "a", status: " M scripts/x.py\n", sha: nil, clean: true, record: { commands.append($0) }).install()
            XCTFail("expected a refusal")
        } catch let error as GitHooksInstaller.InstallError {
            XCTAssertTrue(error.localizedDescription.contains("local changes"))
            XCTAssertFalse(commands.contains { $0.hasPrefix("python3") }, "the installer script must not run")
        } catch { XCTFail("\(error)") }
    }

    func testInstallRunsFromACleanPinnedCheckout() async throws {
        var commands: [String] = []
        try await installer(head: "aaaa", status: "", sha: "aaaa", clean: true, record: { commands.append($0) }).install()
        XCTAssertTrue(commands.contains { $0.hasPrefix("python3") })
    }
}
