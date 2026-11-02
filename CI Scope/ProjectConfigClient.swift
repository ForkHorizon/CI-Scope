// Reads and updates a project's server-held checks over the CI Scope config API.
import Foundation

enum ProjectConfigError: LocalizedError {
    case server(status: Int, code: String)
    case malformedResponse

    var errorDescription: String? {
        switch self {
        case .server(let status, let code): Self.explain(code) + " (HTTP \(status): \(code))"
        case .malformedResponse: "The server sent an unexpected config response."
        }
    }

    static func explain(_ code: String) -> String {
        switch code {
        case "owner_approval_required":
            "This change makes protection weaker and needs the owner's approval. Turn on approvals on the server first."
        case "config_version_conflict": "Someone changed this config first. Reload and try again."
        case "project_config_not_found": "This project is not registered with CI Scope yet."
        case "invalid_config_token": "The config read token does not match the server."
        case "config_read_not_configured": "The server has no config read token set."
        default: code.hasPrefix("invalid_config") ? "The server rejected the config as invalid." : "The change was refused."
        }
    }
}

/// Talks to ci.forkhorizon.com's /api/ci/v2/projects/config (CI-Scope-Web project-config-ingress.ts).
/// Reads use the read-only token; changes use the admin login, and every change carries a Touch ID claim.
struct ProjectConfigClient {
    var baseURL = URL(string: "https://ci.forkhorizon.com/api/ci/v2/projects")!
    var session: URLSession = .shared
    var now: () -> Date = Date.init

    func read(repository: String, readToken: String) async throws -> ProjectConfig {
        var request = URLRequest(url: configURL(query: [URLQueryItem(name: "repository", value: repository)]))
        request.setValue(readToken, forHTTPHeaderField: "x-ci-scope-config-token")
        return try decodeConfig(try await send(request))
    }

    func register(repository: String, admin: (user: String, password: String)) async throws -> ProjectConfig {
        var request = jsonRequest(url: baseURL.appendingPathComponent("config/register"), method: "POST", admin: admin)
        request.httpBody = try JSONSerialization.data(withJSONObject: ["repository": repository])
        return try decodeConfig(try await send(request))
    }

    /// Always sent with an approval claim; the server decides whether the change needs it.
    func update(_ config: ProjectConfig, admin: (user: String, password: String)) async throws -> ProjectConfig {
        var request = jsonRequest(url: configURL(query: []), method: "PUT", admin: admin)
        let encoded = try JSONEncoder().encode(config)
        let approval: [String: Any] = ["method": "touch-id", "approvedAt": Int(now().timeIntervalSince1970 * 1000)]
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "config": try JSONSerialization.jsonObject(with: encoded), "approval": approval,
        ])
        return try decodeConfig(try await send(request))
    }

    private func configURL(query: [URLQueryItem]) -> URL {
        var components = URLComponents(url: baseURL.appendingPathComponent("config"), resolvingAgainstBaseURL: false)!
        components.queryItems = query.isEmpty ? nil : query
        return components.url!
    }

    private func jsonRequest(url: URL, method: String, admin: (user: String, password: String)) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        let credentials = Data("\(admin.user):\(admin.password)".utf8).base64EncodedString()
        request.setValue("Basic " + credentials, forHTTPHeaderField: "authorization")
        return request
    }

    private func decodeConfig(_ body: [String: Any]) throws -> ProjectConfig {
        guard let config = body["config"], JSONSerialization.isValidJSONObject(config) else {
            throw ProjectConfigError.malformedResponse
        }
        do {
            return try JSONDecoder().decode(ProjectConfig.self, from: JSONSerialization.data(withJSONObject: config))
        } catch {
            throw ProjectConfigError.malformedResponse
        }
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
