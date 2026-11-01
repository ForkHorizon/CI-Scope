import Foundation

/// Watches accepted commits of a repository through the user's `gh` login and reports weakened tests.
final class TestScanCache: @unchecked Sendable {
    private let lock = NSLock()
    private var findingsBySHA: [String: [TestFinding]] = [:]

    func findings(for sha: String) -> [TestFinding]? {
        lock.lock()
        defer { lock.unlock() }
        return findingsBySHA[sha]
    }

    func store(_ findings: [TestFinding], for sha: String) {
        lock.lock()
        defer { lock.unlock() }
        findingsBySHA[sha] = findings
    }
}

struct TestProtectionService {
    let github: PolicyGitHub
    var lookback: TimeInterval = 14 * 24 * 3600
    var commitsPerRepository = 15

    func alerts(repository: String, cache: TestScanCache, now: Date = Date()) async throws -> [TestAlert] {
        let branch = try await github.gh(Self.defaultBranchArguments(repository))
        // Merge commits are skipped: their files repeat the commits already on the branch.
        let listing = try await github.gh(
            "api \(quoted("repos/\(repository)/commits?sha=\(branch)&per_page=\(commitsPerRepository)")) --jq '.[] | select((.parents | length) < 2) | [.sha, .commit.committer.date, (.commit.message | split(\"\\n\")[0])] | @tsv'"
        )
        var alerts: [TestAlert] = []
        for line in listing.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 3, isRecent(parts[1], now: now) else { continue }
            let findings = try await findings(repository: repository, sha: parts[0], cache: cache)
            if !findings.isEmpty {
                alerts.append(
                    TestAlert(
                        repository: repository, sha: parts[0], committedAt: parts[1], message: parts[2],
                        findings: findings))
            }
        }
        return alerts
    }

    /// `gh repo view` has no `-R` flag, so the default branch comes from the REST API instead.
    static func defaultBranchArguments(_ repository: String) -> String {
        "api \(shellQuoted("repos/\(repository)")) --jq .default_branch"
    }

    private func findings(repository: String, sha: String, cache: TestScanCache) async throws -> [TestFinding] {
        if let known = cache.findings(for: sha) { return known }
        let json = try await github.gh("api \(quoted("repos/\(repository)/commits/\(sha)")) --jq .files")
        let files = try JSONDecoder().decode([CommitFileChange].self, from: Data(json.utf8))
        let found = TestProtectionDetector.findings(in: files)
        cache.store(found, for: sha)
        return found
    }

    private func isRecent(_ iso: String, now: Date) -> Bool {
        guard let date = ISO8601DateFormatter().date(from: iso) else { return true }
        return now.timeIntervalSince(date) <= lookback
    }

    private func quoted(_ text: String) -> String { Self.shellQuoted(text) }

    private static func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
