import Foundation

/// Opens a pull request that reverts a commit which weakened tests. Never merges it.
struct TestRevertService {
    let config: DashboardConfig

    func openRevertPullRequest(_ alert: TestAlert) async throws -> String {
        guard alert.sha.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil,
            alert.repository.range(of: "^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", options: .regularExpression) != nil
        else { throw PolicyGitHub.Failure.failed("Unexpected repository or commit id.") }
        let branch = "ci-scope/revert-\(alert.shortSHA)"
        let title = "Revert \(alert.shortSHA): \(alert.title.lowercased())"
        let body =
            "Reverts \(alert.sha), which weakened tests (\(alert.findings.map(\.ruleID).joined(separator: ", "))). Opened from CI Scope test protection."
        let script = """
            set -euo pipefail
            work=$(mktemp -d)
            trap 'rm -rf "$work"' EXIT
            cd "$work"
            gh repo clone '\(alert.repository)' repo -- --quiet
            cd repo
            base=$(git rev-parse --abbrev-ref HEAD)
            git checkout -q -b '\(branch)'
            parents=$(git rev-list --parents -n 1 '\(alert.sha)' | wc -w)
            flag=""; [ "$parents" -gt 2 ] && flag="-m 1"
            git -c user.name='CI Scope' -c user.email='ci-scope@users.noreply.github.com' revert --no-edit $flag '\(alert.sha)'
            git push -q --set-upstream origin '\(branch)'
            gh pr create --base "$base" --head '\(branch)' --title '\(title.replacingOccurrences(of: "'", with: ""))' --body '\(body)'
            """
        let result = await ShellClient.run(script, timeout: 240, config: config)
        guard result.exitCode == 0 else {
            throw PolicyGitHub.Failure.failed(String(result.output.trimmed.suffix(400)))
        }
        return result.output.trimmed.split(separator: "\n").last.map(String.init) ?? ""
    }
}
