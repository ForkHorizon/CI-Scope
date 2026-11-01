import Foundation

/// Watches accepted commits of a repository through the user's `gh` login and reports weakened tests.
final class TestScanCache {
    var findingsBySHA: [String: [TestFinding]] = [:]
}

struct TestProtectionService {
    let github: PolicyGitHub
    var lookback: TimeInterval = 14 * 24 * 3600
    var commitsPerRepository = 15

    func alerts(repository: String, cache: TestScanCache, now: Date = Date()) async throws -> [TestAlert] {
        let branch = try await github.gh(
            "repo view -R \(quoted(repository)) --json defaultBranchRef --jq .defaultBranchRef.name")
        let listing = try await github.gh(
            "api \(quoted("repos/\(repository)/commits?sha=\(branch)&per_page=\(commitsPerRepository)")) --jq '.[] | [.sha, .commit.committer.date, (.commit.message | split(\"\\n\")[0])] | @tsv'"
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

    private func findings(repository: String, sha: String, cache: TestScanCache) async throws -> [TestFinding] {
        if let known = cache.findingsBySHA[sha] { return known }
        let json = try await github.gh("api \(quoted("repos/\(repository)/commits/\(sha)")) --jq .files")
        let files = try JSONDecoder().decode([CommitFileChange].self, from: Data(json.utf8))
        let found = TestProtectionDetector.findings(in: files)
        cache.findingsBySHA[sha] = found
        return found
    }

    private func isRecent(_ iso: String, now: Date) -> Bool {
        guard let date = ISO8601DateFormatter().date(from: iso) else { return true }
        return now.timeIntervalSince(date) <= lookback
    }

    private func quoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
