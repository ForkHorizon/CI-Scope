import Foundation

/// Opens a manifest-only policy PR through the GitHub API (no clone): new
/// `ci-scope/policy/…` branch from the base tip, one contents PUT, one `gh pr create`.
extension PolicyGitHub {
    struct ManifestChange {
        let repository: String
        let branch: String
        let text: String
        let blobSHA: String
        let summary: String
    }

    func propose(_ change: ManifestChange) async throws -> PolicyPullRequest {
        let repo = change.repository
        let base = try await gh("api \(quoted("repos/\(repo)/git/ref/heads/\(change.branch)")) --jq .object.sha")
        let stamp = Self.stamp.string(from: Date())
        let name = "\(PolicyProtectedPaths.branchPrefix)\(slug(change.summary))-\(change.branch)-\(stamp)"
        _ = try await gh(
            "api -X POST \(quoted("repos/\(repo)/git/refs")) -f ref=\(quoted("refs/heads/\(name)")) -f sha=\(quoted(base))", attempts: 1)
        let content = Data(change.text.utf8).base64EncodedString()
        _ = try await gh(
            "api -X PUT \(quoted("repos/\(repo)/contents/.ci-scope.json")) -f message=\(quoted("ci-scope policy: \(change.summary)")) -f content=\(quoted(content)) -f sha=\(quoted(change.blobSHA)) -f branch=\(quoted(name))",
            attempts: 1
        )
        let body = "Policy change made in the CI Scope app: \(change.summary). Only `.ci-scope.json` changes."
        let output = try await gh(
            "pr create -R \(quoted(repo)) -B \(quoted(change.branch)) -H \(quoted(name)) -t \(quoted("ci-scope policy: \(change.summary)")) -b \(quoted(body))",
            attempts: 1
        )
        let url = output.split(separator: "\n").last.map(String.init) ?? output
        guard let number = url.split(separator: "/").last.flatMap({ Int($0) }) else {
            throw Failure.failed("Could not read the new PR number from \(url).")
        }
        return PolicyPullRequest(
            number: number, title: change.summary, url: url, state: "OPEN", headRefName: name,
            baseRefName: change.branch, mergeCommit: nil, mergedAt: nil, repository: repo)
    }

    private func slug(_ text: String) -> String {
        text.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }.reduce(into: "") { result, character in
            if !(character == "-" && result.hasSuffix("-")) { result.append(character) }
        }
    }

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMddHHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}
