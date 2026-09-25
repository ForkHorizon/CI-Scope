import Foundation
import XCTest
@testable import CI_Scope

final class PolicyAdminXCTest: XCTestCase {
    private let manifest = """
        {
          "version": 1,
          "checks": [
            {
              "id": "code-linter",
              "type": "code-linter",
              "params": {"mode": "{{auto}}"}
            },
            {
              "id": "go-quality",
              "type": "go-quality"
            },
            {
              "id": "slop-review",
              "type": "slop-review",
              "events": ["pull_request", "workflow_dispatch"],
              "resources": ["ollama"],
              "params": {"model": "qwen3-coder:30b-a3b-q4_K_M"}
            }
          ]
        }

        """

    func testProtectedPathsMirrorServerGlobs() {
        XCTAssertTrue(PolicyProtectedPaths.matches(".ci-scope.json"))
        XCTAssertTrue(PolicyProtectedPaths.matches(".github/workflows/ci.yml"))
        XCTAssertTrue(PolicyProtectedPaths.matches("CI Scope/nested/.code-linter.json"))
        XCTAssertFalse(PolicyProtectedPaths.matches("CI Scope/App.swift"))
        XCTAssertFalse(PolicyProtectedPaths.matches("x.ci-scope.json"))
    }

    func testPolicyBranchOnlyForProtectedOnlyChanges() {
        let workflow = [".github/workflows/code-linter.yml", ".code-linter.json"]
        XCTAssertEqual(
            PolicyProtectedPaths.branch("ci-scope/install-code-linter", forFiles: workflow),
            "ci-scope/policy/install-code-linter")
        XCTAssertEqual(
            PolicyProtectedPaths.branch("ci-scope/install-x", forFiles: workflow + ["scripts/run.sh"]),
            "ci-scope/install-x")
        XCTAssertEqual(PolicyProtectedPaths.branch("ci-scope/policy/a", forFiles: workflow), "ci-scope/policy/a")
    }

    func testRemovingLastCheckDropsOnlyItsBlock() throws {
        let edited = try PolicyManifestEditor.removing("slop-review", from: manifest)
        XCTAssertEqual(PolicyManifestEditor.checkIDs(in: edited), ["code-linter", "go-quality"])
        let expected = manifest.replacingOccurrences(
            of: """
                },
                    {
                      "id": "slop-review",
                      "type": "slop-review",
                      "events": ["pull_request", "workflow_dispatch"],
                      "resources": ["ollama"],
                      "params": {"model": "qwen3-coder:30b-a3b-q4_K_M"}
                    }
                """,
            with: "}")
        XCTAssertEqual(edited, expected)
    }

    func testRemovingFirstCheckKeepsBracesInsideStrings() throws {
        let edited = try PolicyManifestEditor.removing("code-linter", from: manifest)
        XCTAssertEqual(PolicyManifestEditor.checkIDs(in: edited), ["go-quality", "slop-review"])
        XCTAssertFalse(edited.contains("{{auto}}"))
        XCTAssertNoThrow(try PolicyManifestEditor.validate(edited))
    }

    func testAddingAppendsTemplateWithMatchingIndent() throws {
        let edited = try PolicyManifestEditor.adding("swift-compile", to: manifest)
        XCTAssertEqual(
            PolicyManifestEditor.checkIDs(in: edited), ["code-linter", "go-quality", "slop-review", "swift-compile"])
        XCTAssertTrue(edited.contains("},\n    {\"id\": \"swift-compile\""))
        XCTAssertThrowsError(try PolicyManifestEditor.adding("go-quality", to: manifest))
    }

    func testValidationRejectsDanglingDependencyAndNoRequiredCheck() throws {
        let dependent = manifest.replacingOccurrences(
            of: #""type": "go-quality""#, with: #""type": "go-quality", "depends_on": ["code-linter"]"#)
        XCTAssertThrowsError(try PolicyManifestEditor.removing("code-linter", from: dependent))
        let withoutLinter = try PolicyManifestEditor.removing("code-linter", from: manifest)
        XCTAssertThrowsError(try PolicyManifestEditor.removing("go-quality", from: withoutLinter))
    }

    func testRecordPathsAddNewProtectedFilesAndDropDeletedOnes() throws {
        let current: PolicyRecordBuilder.Record = [
            "files": [["path": ".ci-scope.json", "sha256": "x"], ["path": ".github/workflows/old.yml", "sha256": "y"]],
            "protected_patterns": [".github/workflows/**", ".ci-scope.json"],
        ]
        let tree = [".ci-scope.json", ".github/workflows/new.yml", "README.md"]
        XCTAssertEqual(
            try PolicyRecordBuilder.protectedPaths(current: current, treePaths: tree),
            [".ci-scope.json", ".github/workflows/new.yml"])
    }

    func testRecordRehashesFilesAndDerivesChecks() throws {
        let current: PolicyRecordBuilder.Record = [
            "version": 1, "repository": "ForkHorizon/X", "branch": "main", "approved_sha": String(repeating: "a", count: 40),
            "signature": ["value": "old"], "policy_digest": "old", "approved_by": "me", "approved_at": "then",
            "files": [], "protected_patterns": [],
        ]
        let edited = try PolicyManifestEditor.removing("go-quality", from: manifest)
        let files = [".ci-scope.json": Data(edited.utf8), "abc": Data("abc".utf8)]
        let record = try PolicyRecordBuilder.record(
            current: current, mergeSHA: String(repeating: "b", count: 40), files: files)
        XCTAssertEqual(PolicyRecordBuilder.approvedSHA(record), String(repeating: "b", count: 40))
        XCTAssertNil(record["signature"])
        XCTAssertNil(record["policy_digest"])
        XCTAssertNil(record["approved_by"])
        let digests = (record["files"] as? [[String: String]])?.reduce(into: [:]) { $0[$1["path"]!] = $1["sha256"] }
        XCTAssertEqual(digests?["abc"], "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        let checks = record["checks"] as? [[String: Any]] ?? []
        XCTAssertEqual(checks.compactMap { $0["id"] as? String }, ["code-linter", "slop-review"])
        XCTAssertEqual(checks.compactMap { $0["required"] as? Bool }, [true, false])
    }
}
