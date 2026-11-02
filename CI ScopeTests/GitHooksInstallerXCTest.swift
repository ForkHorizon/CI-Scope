import Foundation
import XCTest
@testable import CI_Scope

final class GitHooksInstallerXCTest: XCTestCase {
    private let gates = URL(fileURLWithPath: "/tmp/gates dir")
    private let hooks = URL(fileURLWithPath: "/tmp/ci-hooks")

    private func installer(hooksPath: String, exit: Int32 = 0, record: @escaping (String) -> Void = { _ in }) -> GitHooksInstaller {
        GitHooksInstaller(gatesRoot: gates, hooksDirectory: hooks, run: { command in
            record(command)
            return command.hasPrefix("git config") ? ShellResult(exitCode: 0, output: hooksPath + "\n") : ShellResult(exitCode: exit, output: "log")
        })
    }

    func testStateReflectsTheGlobalHooksPath() async {
        let none = await installer(hooksPath: "").state()
        let ours = await installer(hooksPath: "/tmp/ci-hooks").state()
        let other = await installer(hooksPath: "/somewhere/else").state()
        XCTAssertEqual(none, .notInstalled)
        XCTAssertEqual(ours, .installed)
        XCTAssertEqual(other, .otherHooksPath("/somewhere/else"))
    }

    func testInstallRunsTheQuotedInstallerScript() async throws {
        var commands: [String] = []
        try await installer(hooksPath: "", record: { commands.append($0) }).install()
        let script = try XCTUnwrap(commands.last)
        XCTAssertTrue(script.hasPrefix("python3 "))
        XCTAssertTrue(script.contains("/tmp/gates dir/scripts/install_hooks.py"))
        XCTAssertTrue(script.hasSuffix("/tmp/ci-hooks'") || script.hasSuffix("/tmp/ci-hooks"))
    }

    func testInstallNeverReplacesSomeoneElsesHooksPath() async {
        var commands: [String] = []
        do {
            try await installer(hooksPath: "/somewhere/else", record: { commands.append($0) }).install()
            XCTFail("expected a refusal")
        } catch {
            XCTAssertEqual(error as? GitHooksInstaller.InstallError, .otherHooksPath("/somewhere/else"))
        }
        XCTAssertFalse(commands.contains { $0.hasPrefix("python3") })
    }

    func testAFailingInstallerIsReported() async {
        do {
            try await installer(hooksPath: "", exit: 2).install()
            XCTFail("expected a failure")
        } catch {
            XCTAssertEqual(error as? GitHooksInstaller.InstallError, .failed("log"))
        }
    }
}
