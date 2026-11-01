import Foundation

enum PolicyServerError: LocalizedError {
    case server(status: Int, code: String)
    case malformedResponse

    var errorDescription: String? {
        switch self {
        case .server(let status, let code): Self.explain(code) + " (HTTP \(status): \(code))"
        case .malformedResponse: "The policy server sent an unexpected response."
        }
    }

    static func explain(_ code: String) -> String {
        switch code {
        case "policy_not_found": "This branch has no trusted policy yet."
        case "admin_login_rejected":
            "The server rejected the admin login (user = your GitHub login, password = keychain admin-password). Nothing new was merged."
        case "invalid_policy_token": "The policy read token in the keychain doesn't match the server."
        case "policy_pr_not_approved": "The PR is not a merged ci-scope/policy/ PR into this branch."
        case "policy_pr_changed_unprotected_file": "The policy PR also changed non-protected files."
        case "policy_actor_mismatch": "The admin user must be the GitHub account that merged the PR."
        case "policy_checks_mismatch": "The record's checks don't match .ci-scope.json at the merge commit."
        case "policy_gates_pin_missing": "No workflow at the merge commit pins the approved ci-gates SHA."
        case "policy_changed_during_activation": "Someone activated this branch at the same time. Refresh and retry."
        case _ where code.hasPrefix("policy_pr_unavailable:404"):
            "The server's GitHub token (CI_SCOPE_GITHUB_TOKEN) can't see this repo. Add the repo to that token's repository access on GitHub, then Retry."
        default:
            code.hasPrefix("policy_file_digest_mismatch") ? "A protected file changed after the merge." : "Activation was refused."
        }
    }
}

/// Talks to ci.forkhorizon.com's /api/ci/policy (CI-Scope-Web policy.ts).
struct PolicyServerClient {
    var baseURL = URL(string: "https://ci.forkhorizon.com/api/ci/policy")!

    func currentRecord(repository: String, branch: String, readToken: String) async throws
        -> PolicyRecordBuilder.Record
    {
        var request = URLRequest(url: endpoint(repository: repository, branch: branch))
        request.setValue(readToken, forHTTPHeaderField: "x-ci-scope-policy-token")
        let body = try await send(request)
        guard let record = body["record"] as? PolicyRecordBuilder.Record else {
            throw PolicyServerError.malformedResponse
        }
        return record
    }

    func activate(_ record: PolicyRecordBuilder.Record, pullRequest: Int, admin: (user: String, password: String))
        async throws
    {
        guard let repository = record["repository"] as? String, let branch = record["branch"] as? String else {
            throw PolicyServerError.malformedResponse
        }
        var request = URLRequest(url: endpoint(repository: repository, branch: branch))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(basicAuth(admin.user, admin.password), forHTTPHeaderField: "authorization")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["record": record, "policy_pr": ["number": pullRequest]])
        _ = try await send(request)
    }

    /// Read-only check of the admin login (same credentials as activation), so a wrong
    /// password is caught before anything is merged.
    func verifyAdmin(user: String, password: String) async throws {
        var request = URLRequest(url: baseURL.deletingLastPathComponent().appendingPathComponent("admin/status"))
        request.setValue(basicAuth(user, password), forHTTPHeaderField: "authorization")
        do {
            _ = try await send(request)
        } catch PolicyServerError.server(let status, _) where status == 401 {
            throw PolicyServerError.server(status: 401, code: "admin_login_rejected")
        }
    }

    /// Network-level failures only (no HTTP answer). Re-sending an activation is safe: the
    /// server re-verifies and just bumps the policy version.
    private func dataWithRetry(_ request: URLRequest) async throws -> (Data, URLResponse) {
        for attempt in 1..<3 {
            do { return try await URLSession.shared.data(for: request) } catch is URLError {
                try await Task.sleep(for: .seconds(2 * attempt))
            }
        }
        return try await URLSession.shared.data(for: request)
    }

    private func basicAuth(_ user: String, _ password: String) -> String {
        "Basic " + Data("\(user):\(password)".utf8).base64EncodedString()
    }

    private func endpoint(repository: String, branch: String) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "repository", value: repository), URLQueryItem(name: "branch", value: branch),
        ]
        return components.url!
    }

    private func send(_ request: URLRequest) async throws -> [String: Any] {
        var request = request
        request.timeoutInterval = 30
        let (data, response) = try await dataWithRetry(request)
        let body = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw PolicyServerError.server(status: status, code: body["error"] as? String ?? "unknown")
        }
        return body
    }
}
