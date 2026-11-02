// Fetches open security events from the CI Scope server and acknowledges them.
import Foundation

/// Talks to ci.forkhorizon.com's /api/ci/v2/events (CI-Scope-Web security-events-ingress.ts).
struct SecurityEventsClient {
    var baseURL = URL(string: "https://ci.forkhorizon.com/api/ci/v2/events")!
    var session: URLSession = .shared

    func fetchOpen(readToken: String) async throws -> [SecurityEvent] {
        var request = URLRequest(url: baseURL)
        request.setValue(readToken, forHTTPHeaderField: "x-ci-scope-config-token")
        let body = try await send(request)
        guard let events = body["events"], JSONSerialization.isValidJSONObject(events) else {
            throw ProjectConfigError.malformedResponse
        }
        do {
            return try JSONDecoder().decode([SecurityEvent].self, from: JSONSerialization.data(withJSONObject: events))
        } catch {
            throw ProjectConfigError.malformedResponse
        }
    }

    func acknowledge(ids: [Int], admin: (user: String, password: String)) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("ack"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        let credentials = Data("\(admin.user):\(admin.password)".utf8).base64EncodedString()
        request.setValue("Basic " + credentials, forHTTPHeaderField: "authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["ids": ids])
        _ = try await send(request)
    }

    private func send(_ request: URLRequest) async throws -> [String: Any] {
        var request = request
        request.timeoutInterval = 30
        let (data, response) = try await session.data(for: request)
        let body = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw ProjectConfigError.server(status: status, code: body["error"] as? String ?? "unknown")
        }
        return body
    }
}
