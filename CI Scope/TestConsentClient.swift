import Foundation

/// Talks to ci.forkhorizon.com's /api/ci/test-consent (CI-Scope-Web test-consent.ts):
/// reads the decision history with the read token, records decisions with the owner's admin login.
struct TestConsentClient {
    var baseURL = URL(string: "https://ci.forkhorizon.com/api/ci/test-consent")!

    func decisions(repository: String, readToken: String, limit: Int = 200) async throws -> [TestDecision] {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "repository", value: repository), URLQueryItem(name: "limit", value: String(limit)),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(readToken, forHTTPHeaderField: "x-ci-scope-policy-token")
        let body = try await send(request)
        guard let rows = body["decisions"] as? [[String: Any]] else { throw PolicyServerError.malformedResponse }
        return rows.compactMap(Self.decision)
    }

    func record(_ draft: TestDecisionDraft, admin: (user: String, password: String)) async throws {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("ci-scope-app", forHTTPHeaderField: "x-ci-scope-client")
        let credentials = Data("\(admin.user):\(admin.password)".utf8).base64EncodedString()
        request.setValue("Basic " + credentials, forHTTPHeaderField: "authorization")
        var payload: [String: Any] = [
            "repository": draft.repository, "sha": draft.sha, "decision": draft.decision,
        ]
        if let path = draft.path { payload["path"] = path }
        if let note = draft.note { payload["note"] = note }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        _ = try await send(request)
    }

    static func decision(_ row: [String: Any]) -> TestDecision? {
        guard let repository = row["repository"] as? String, let sha = row["sha"] as? String,
            let decision = row["decision"] as? String, let by = row["decidedBy"] as? String,
            let at = row["decidedAt"] as? String
        else { return nil }
        return TestDecision(
            repository: repository, sha: sha, decision: decision, path: row["path"] as? String,
            note: row["note"] as? String, mutedUntil: row["mutedUntil"] as? String, decidedBy: by, decidedAt: at)
    }

    private func send(_ request: URLRequest) async throws -> [String: Any] {
        var request = request
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        let body = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw PolicyServerError.server(status: status, code: body["error"] as? String ?? "unknown")
        }
        return body
    }
}

struct TestDecisionDraft {
    let repository: String
    let sha: String
    let decision: String
    var path: String?
    var note: String?
}
