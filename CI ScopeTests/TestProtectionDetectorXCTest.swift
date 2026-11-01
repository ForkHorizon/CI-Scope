import XCTest

@testable import CI_Scope

final class TestProtectionDetectorXCTest: XCTestCase {
    private func file(
        _ name: String, status: String = "modified", previous: String? = nil,
        lines: (added: Int, removed: Int) = (1, 0), patch: String? = nil
    ) -> CommitFileChange {
        CommitFileChange(
            filename: name, status: status, previousFilename: previous, additions: lines.added,
            deletions: lines.removed, patch: patch)
    }

    func testDefaultPatternsCoverEachStack() {
        for path in [
            "tests/test_a.py", "pkg/a_test.go", "src/a.spec.ts", "Tests/AppTests.swift", "Assets/Tests/Edit/Foo.cs",
        ] {
            XCTAssertTrue(TestProtectionDetector.isTestPath(path), path)
        }
        for path in ["src/app.py", "main.go", "README.md"] {
            XCTAssertFalse(TestProtectionDetector.isTestPath(path), path)
        }
    }

    func testChangedDeletedAndRenamedTestsAreHigh() {
        let found = TestProtectionDetector.findings(in: [
            file("tests/test_a.py", lines: (1, 1)),
            file("pkg/b_test.go", status: "removed"),
            file("tests/test_c.py", status: "renamed", previous: "tests/test_old.py"),
        ])
        XCTAssertEqual(found.map(\.ruleID), ["test-modified", "test-deleted", "test-renamed"])
        XCTAssertTrue(found.allSatisfy { $0.severity == .high })
        XCTAssertEqual(found[2].path, "tests/test_old.py")
    }

    func testPureAdditionsAndNewTestsAreAllowed() {
        XCTAssertTrue(
            TestProtectionDetector.findings(in: [
                file("tests/test_a.py", lines: (5, 0)), file("tests/test_new.py", status: "added"),
                file("app.py", lines: (1, 3)),
            ]).isEmpty)
    }

    func testRunnerConfigChangeIsHigh() {
        let found = TestProtectionDetector.findings(in: [file("pytest.ini"), file("Makefile")])
        XCTAssertEqual(found.map(\.ruleID), ["runner-config-changed", "runner-config-changed"])
    }

    func testAddedSkipIsMediumUnlessJustified() {
        let skip = "@@ -0,0 +1,2 @@\n+@pytest.mark.skip\n+def test_x(): pass"
        let justified = "@@ -0,0 +1 @@\n+@pytest.mark.skip  # allow-skip: needs GPU"
        let removedLine = "@@ -1 +0,0 @@\n-@pytest.mark.skip"
        XCTAssertEqual(
            TestProtectionDetector.findings(in: [file("tests/test_new.py", status: "added", patch: skip)]).map(\.severity),
            [.medium])
        XCTAssertTrue(
            TestProtectionDetector.findings(in: [file("tests/test_new.py", status: "added", patch: justified)]).isEmpty)
        XCTAssertTrue(
            TestProtectionDetector.findings(in: [file("tests/test_new.py", status: "modified", patch: removedLine)])
                .isEmpty)
    }

    func testAlertSeverityTitleAndMuteHandling() {
        let findings = [
            TestFinding(severity: .medium, ruleID: "test-skip-added", path: "a", message: "m"),
            TestFinding(severity: .high, ruleID: "test-modified", path: "b", message: "m"),
        ]
        var alert = TestAlert(
            repository: "o/r", sha: String(repeating: "a", count: 40), committedAt: "t", message: "x", findings: findings)
        XCTAssertEqual(alert.severity, .high)
        XCTAssertEqual(alert.shortSHA, "aaaaaaa")
        XCTAssertTrue(alert.isOpen())
        let muted = TestDecision(
            repository: "o/r", sha: alert.sha, decision: "muted", path: nil, note: nil,
            mutedUntil: "2999-01-01T00:00:00Z", decidedBy: "me", decidedAt: "t")
        alert.decision = muted
        XCTAssertFalse(alert.isOpen())
        alert.decision = TestDecision(
            repository: "o/r", sha: alert.sha, decision: "muted", path: nil, note: nil,
            mutedUntil: "2000-01-01T00:00:00Z", decidedBy: "me", decidedAt: "t")
        XCTAssertTrue(alert.isOpen())
        alert.decision = TestDecision(
            repository: "o/r", sha: alert.sha, decision: "approved", path: nil, note: nil, mutedUntil: nil,
            decidedBy: "me", decidedAt: "t")
        XCTAssertFalse(alert.isOpen())
    }
}
