// Asks the server for an owner approval, sends the owner to the website to sign it with Touch ID, waits for it.
import Foundation

extension ProjectConfigClient {
    /// Returns the id of an approved request for exactly this config; the next save spends it once.
    func approve(_ config: ProjectConfig, admin: (user: String, password: String)) async throws -> String {
        var request = jsonRequest(url: approvalsURL("request"), method: "POST", admin: admin)
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "kind": "config", "repository": config.repository,
            "config": try JSONSerialization.jsonObject(with: try JSONEncoder().encode(config)),
        ])
        let reply = try await send(request)
        guard let id = reply["id"] as? String, let path = reply["path"] as? String,
            let page = URL(string: path, relativeTo: baseURL)?.absoluteURL
        else { throw ProjectConfigError.malformedResponse }
        open(page)
        try await waitUntilApproved(id)
        return id
    }

    private func waitUntilApproved(_ id: String) async throws {
        var status = URLComponents(url: approvalsURL("status"), resolvingAgainstBaseURL: false)!
        status.queryItems = [URLQueryItem(name: "id", value: id)]
        let deadline = ContinuousClock.now + approvalTimeout
        while ContinuousClock.now < deadline {
            let reply = try await send(URLRequest(url: status.url!))
            if reply["state"] as? String == "approved" { return }
            if ["used", "expired"].contains(reply["state"] as? String) { break }
            try await Task.sleep(for: pollInterval)
        }
        throw ProjectConfigError.approvalTimedOut
    }

    private func approvalsURL(_ name: String) -> URL {
        baseURL.deletingLastPathComponent().appendingPathComponent("approvals").appendingPathComponent(name)
    }
}
