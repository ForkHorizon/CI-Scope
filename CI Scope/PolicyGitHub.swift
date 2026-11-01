import Foundation

struct PolicyPullRequest: Decodable, Identifiable, Equatable {
    struct Commit: Decodable, Equatable { let oid: String }

    let number: Int
    let title: String
    let url: String
    let state: String
    let headRefName: String
    let baseRefName: String
    let mergeCommit: Commit?
    let mergedAt: String?
    var repository = ""

    var id: String { "\(repository)#\(number)" }

    private enum CodingKeys: String, CodingKey {
        case number, title, url, state, headRefName, baseRefName, mergeCommit, mergedAt
    }
}

/// Every GitHub read/write the policy flow needs, through the user's `gh` login.
struct PolicyGitHub {
    enum Failure: LocalizedError {
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .failed(let detail): "GitHub: \(detail)"
            }
        }
    }

    let config: DashboardConfig

    func policyPullRequests(repository: String) async throws -> [PolicyPullRequest] {
        let fields = "number,title,url,state,headRefName,baseRefName,mergeCommit,mergedAt"
        let output = try await gh("pr list -R \(quoted(repository)) --state all -L 40 --json \(fields)")
        let all = try JSONDecoder().decode([PolicyPullRequest].self, from: Data(output.utf8))
        return all.filter { $0.headRefName.hasPrefix(PolicyProtectedPaths.branchPrefix) && $0.state != "CLOSED" }
            .map { pullRequest in
                var copy = pullRequest
                copy.repository = repository
                return copy
            }
    }

    func mergeWithBypass(_ pullRequest: PolicyPullRequest) async throws -> String {
        let target = "\(pullRequest.number) -R \(quoted(pullRequest.repository))"
        // Live state, not the cached list: a retry after a merge must not merge again.
        if try await gh("pr view \(target) --json state --jq .state") != "MERGED" {
            _ = try await gh("pr merge \(target) --merge --admin", attempts: 1)
        }
        let sha = try await gh("pr view \(target) --json mergeCommit --jq .mergeCommit.oid")
        guard sha.count == 40 else { throw Failure.failed("PR #\(pullRequest.number) has no merge commit yet.") }
        return sha
    }

    func login() async throws -> String {
        try await gh("api user --jq .login")
    }

    func treePaths(repository: String, sha: String) async throws -> [String] {
        let truncated = try await gh("api \(quoted("repos/\(repository)/git/trees/\(sha)?recursive=1")) --jq .truncated")
        guard truncated == "false" else { throw Failure.failed("The repository tree is too large to list.") }
        let paths = try await gh(
            "api \(quoted("repos/\(repository)/git/trees/\(sha)?recursive=1")) --jq '.tree[] | select(.type == \"blob\") | .path'"
        )
        return paths.split(separator: "\n").map(String.init)
    }

    /// Raw bytes via base64 so digests match exactly (shell output is text-sanitized).
    func file(repository: String, ref: String, path: String) async throws -> (data: Data, blobSHA: String) {
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        let url = "repos/\(repository)/contents/\(encoded)?ref=\(ref)"
        let lines = try await gh("api \(quoted(url)) --jq '.sha, (.content | gsub(\"\\n\"; \"\"))'")
            .split(separator: "\n").map(String.init)
        guard lines.count == 2, let data = Data(base64Encoded: lines[1]) else {
            throw Failure.failed("Could not read \(path) at \(ref).")
        }
        return (data, lines[0])
    }

    /// Reads retry (flaky hotspot DNS drops calls); writes pass `attempts: 1` and rely on
    /// the pipeline re-checking live state on the next run instead.
    func gh(_ arguments: String, attempts: Int = 3) async throws -> String {
        var result = ShellResult(exitCode: 1, output: "")
        for attempt in 1...max(1, attempts) {
            result = await ShellClient.run("NO_COLOR=1 gh \(arguments)", timeout: 60, config: config)
            if result.exitCode == 0 { return result.output.trimmed }
            if attempt < attempts { try await Task.sleep(for: .seconds(2 * attempt)) }
        }
        throw Failure.failed(String(result.output.trimmed.suffix(400)))
    }
}
