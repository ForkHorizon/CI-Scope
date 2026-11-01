import XCTest

@testable import CI_Scope

final class LocalCheckResultXCTest: XCTestCase {
    private let json = """
        {"checks":[{"duration_ms":521,"id":"code-linter","status":"passed"},
        {"duration_ms":115,"id":"web-tests","status":"failed"}],
        "dirty":true,"finished_at":"2026-10-31T21:04:45.127388+00:00",
        "git_head":"95cac80","slow":["web-tests"],"started_at":"x","status":"failed","tier":"full"}
        """

    private func decode(_ text: String) throws -> LocalCheckResult {
        try JSONDecoder().decode(LocalCheckResult.self, from: Data(text.utf8))
    }

    private func run(sha: String?, conclusion: String?, updatedAt: String = "2026-11-01T10:00:00Z") -> GitHubRun {
        GitHubRun(
            databaseId: 1, attempt: 1, status: conclusion == nil ? "in_progress" : "completed",
            conclusion: conclusion, displayTitle: "t", workflowName: "CI Scope", headBranch: "main",
            headSha: sha, event: "pull_request", createdAt: updatedAt, updatedAt: updatedAt, url: "u")
    }

    func testDecodesCompactResultWithMicrosecondTimestamp() throws {
        let result = try decode(json)
        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.failedChecks.map(\.id), ["web-tests"])
        XCTAssertTrue(result.dirty)
        XCTAssertNotNil(result.finishedDate)
    }

    func testFileNameMatchesWhatTheCheckWrapperWrites() {
        XCTAssertEqual(LocalCheckStore.fileName(for: "ForkHorizon/CI-Scope-Web"), "ForkHorizon-CI-Scope-Web.json")
    }

    func testStoreReturnsNilForMissingOrBrokenFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        XCTAssertNil(LocalCheckStore.load(repositorySlug: "a/b", directory: directory))
        try Data("not json".utf8).write(to: directory.appendingPathComponent("a-b.json"))
        XCTAssertNil(LocalCheckStore.load(repositorySlug: "a/b", directory: directory))
        try Data(json.utf8).write(to: directory.appendingPathComponent("a-b.json"))
        XCTAssertEqual(LocalCheckStore.load(repositorySlug: "a/b", directory: directory)?.gitHead, "95cac80")
    }

    func testVerdictComparesLocalAgainstCIForTheSameCommit() throws {
        let red = try decode(json)
        let green = try decode(json.replacingOccurrences(of: "\"status\":\"failed\",\"tier\"", with: "\"status\":\"passed\",\"tier\""))
        XCTAssertEqual(LocalCheckComparison.verdict(local: green, runs: [run(sha: "95cac80", conclusion: "failure")]), .localGreenCIRed)
        XCTAssertEqual(LocalCheckComparison.verdict(local: red, runs: [run(sha: "95cac80", conclusion: "success")]), .localRedCIGreen)
        XCTAssertEqual(LocalCheckComparison.verdict(local: red, runs: [run(sha: "95cac80", conclusion: "failure")]), .agree)
        XCTAssertEqual(LocalCheckComparison.verdict(local: red, runs: [run(sha: "95cac80", conclusion: nil)]), .ciPending)
        XCTAssertEqual(LocalCheckComparison.verdict(local: red, runs: [run(sha: "other", conclusion: "success")]), .ciNotRun)
    }

    func testVerdictUsesTheNewestRunOfTheCommit() throws {
        let green = try decode(json.replacingOccurrences(of: "\"status\":\"failed\",\"tier\"", with: "\"status\":\"passed\",\"tier\""))
        let runs = [
            run(sha: "95cac80", conclusion: "failure", updatedAt: "2026-11-01T09:00:00Z"),
            run(sha: "95cac80", conclusion: "success", updatedAt: "2026-11-01T11:00:00Z"),
        ]
        XCTAssertEqual(LocalCheckComparison.verdict(local: green, runs: runs), .agree)
    }
}
