import Foundation

enum PolicyChangeStatus: Equatable {
    case awaitingMerge
    case awaitingActivation
    case active
    case working(String)
    case failed(String)

    var needsApproval: Bool {
        self == .awaitingMerge || self == .awaitingActivation
    }
}

/// Approve pipeline for one policy PR: admin merge, rebuild the record at the merge
/// commit, activate it, then re-read the server to prove the new policy is live.
/// Safe to retry: a merged PR skips straight to activation.
struct PolicyAdminService {
    var github = PolicyGitHub(config: DashboardConfig())
    var server = PolicyServerClient()

    func status(of pullRequest: PolicyPullRequest, readToken: String) async -> PolicyChangeStatus {
        guard pullRequest.state == "MERGED", let merge = pullRequest.mergeCommit?.oid else { return .awaitingMerge }
        do {
            let record = try await server.currentRecord(
                repository: pullRequest.repository, branch: pullRequest.baseRefName, readToken: readToken)
            if PolicyRecordBuilder.approvedSHA(record) == merge { return .active }
            // Merged before the live policy was approved = superseded, not pending.
            let approvedAt = record["approved_at"] as? String ?? ""
            return (pullRequest.mergedAt ?? "") > approvedAt ? .awaitingActivation : .active
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func approve(
        _ pullRequest: PolicyPullRequest,
        credentials: (password: String, readToken: String),
        progress: @escaping @MainActor (String) -> Void
    ) async throws {
        let repository = pullRequest.repository
        let branch = pullRequest.baseRefName
        await progress("Checking admin login…")
        let user = try await github.login()
        try await server.verifyAdmin(user: user, password: credentials.password)
        await progress(pullRequest.state == "MERGED" ? "Already merged" : "Merging with admin bypass…")
        let sha = try await github.mergeWithBypass(pullRequest)

        await progress("Building policy record…")
        let current = try await server.currentRecord(
            repository: repository, branch: branch, readToken: credentials.readToken)
        let tree = try await github.treePaths(repository: repository, sha: sha)
        var files: [String: Data] = [:]
        for path in try PolicyRecordBuilder.protectedPaths(current: current, treePaths: tree) {
            files[path] = try await github.file(repository: repository, ref: sha, path: path).data
        }
        let record = try PolicyRecordBuilder.record(current: current, mergeSHA: sha, files: files)

        await progress("Activating…")
        try await server.activate(record, pullRequest: pullRequest.number, admin: (user, credentials.password))

        let live = try await server.currentRecord(
            repository: repository, branch: branch, readToken: credentials.readToken)
        guard PolicyRecordBuilder.approvedSHA(live) == sha else {
            throw PolicyGitHub.Failure.failed("The server accepted activation but still reports the old policy.")
        }
    }
}
