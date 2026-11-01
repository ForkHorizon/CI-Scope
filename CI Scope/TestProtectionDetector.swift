import Foundation

/// File entry of a commit as returned by `GET /repos/{repo}/commits/{sha}`.
struct CommitFileChange: Decodable, Equatable {
    let filename: String
    let status: String
    let previousFilename: String?
    let additions: Int
    let deletions: Int
    let patch: String?

    private enum CodingKeys: String, CodingKey {
        case filename, status, additions, deletions, patch
        case previousFilename = "previous_filename"
    }
}

enum TestAlertSeverity: String, Equatable, Comparable {
    case medium
    case high

    static func < (left: Self, right: Self) -> Bool { left == .medium && right == .high }
}

struct TestFinding: Equatable {
    let severity: TestAlertSeverity
    let ruleID: String
    let path: String
    let message: String
}

/// Mirrors ci-gates `scripts/test_protection.py` (same default patterns and rules), applied to a
/// commit's file list from the GitHub API so the app can watch accepted commits without a clone.
enum TestProtectionDetector {
    static let testPatterns = [
        #"(^|/)tests?/"#, #"(^|/)Tests/"#, #"(^|/)__tests__/"#, #"(^|/)Assets/Tests/"#,
        #"_test\.go$"#, #"_test\.py$"#, #"(^|/)test_[^/]*\.py$"#,
        #"\.(spec|test)\.(ts|tsx|js|jsx|mjs|cjs)$"#, #"Tests?\.(swift|cs|kt|java)$"#,
    ]
    static let runnerFiles = [
        #"(^|/)(pytest|tox)\.ini$"#, #"(^|/)conftest\.py$"#, #"(^|/)(jest|vitest)\.config\.[a-z]+$"#,
        #"(^|/)Makefile$"#,
    ]
    static let skipMarker =
        #"\.skip\(|\b(?:xit|xdescribe|xtest)\(|@Disabled\b|\bt\.Skip(?:Now|f)?\(|pytest\.mark\.skip|@unittest\.skip|XCTSkip\b"#

    static func isTestPath(_ path: String) -> Bool {
        testPatterns.contains { path.range(of: $0, options: .regularExpression) != nil }
    }

    static func findings(in files: [CommitFileChange]) -> [TestFinding] {
        files.flatMap { fileFindings($0) }
    }

    private static func fileFindings(_ file: CommitFileChange) -> [TestFinding] {
        var found: [TestFinding] = []
        switch file.status {
        case "modified" where isTestPath(file.filename) && file.deletions > 0:
            found.append(high("test-modified", file.filename, "existing test file has removed or changed lines"))
        case "removed" where isTestPath(file.filename):
            found.append(high("test-deleted", file.filename, "existing test file was deleted"))
        case "renamed" where isTestPath(file.previousFilename ?? file.filename):
            let old = file.previousFilename ?? file.filename
            found.append(high("test-renamed", old, "existing test file was renamed to \(file.filename)"))
        default:
            if ["modified", "renamed"].contains(file.status), isRunnerFile(file.filename) {
                found.append(high("runner-config-changed", file.filename, "test runner configuration changed"))
            }
        }
        if isTestPath(file.filename), addsUnjustifiedSkip(file.patch) {
            found.append(
                TestFinding(
                    severity: .medium, ruleID: "test-skip-added", path: file.filename,
                    message: "a skip marker was added to a test"))
        }
        return found
    }

    private static func high(_ rule: String, _ path: String, _ message: String) -> TestFinding {
        TestFinding(severity: .high, ruleID: rule, path: path, message: message)
    }

    private static func isRunnerFile(_ path: String) -> Bool {
        runnerFiles.contains { path.range(of: $0, options: .regularExpression) != nil }
    }

    private static func addsUnjustifiedSkip(_ patch: String?) -> Bool {
        guard let patch else { return false }
        return patch.split(separator: "\n").contains { line in
            line.hasPrefix("+") && !line.hasPrefix("+++")
                && line.range(of: skipMarker, options: .regularExpression) != nil
                && line.range(of: #"allow-skip:\s*\S"#, options: .regularExpression) == nil
        }
    }
}
