// Reads and updates a project's server-held checks over the CI Scope config API.
import AppKit
import Foundation

enum ProjectConfigError: LocalizedError {
    case server(status: Int, code: String)
    case malformedResponse
    case approvalTimedOut

    var errorDescription: String? {
        switch self {
        case .server(let status, let code): Self.explain(code) + " (HTTP \(status): \(code))"
        case .malformedResponse: "The server sent an unexpected config response."
        case .approvalTimedOut: "The change was not approved with Touch ID on the website in time. Nothing was changed."
        }
    }

    static func explain(_ code: String) -> String {
        switch code {
        case "owner_approval_required":
            "This change makes protection weaker and needs the owner's approval with Touch ID on the website."
        case "config_version_conflict": "Someone changed this config first. Reload and try again."
        case "project_config_not_found": "This project is not registered with CI Scope yet."
        case "invalid_config_token": "The config read token does not match the server."
        case "config_read_not_configured": "The server has no config read token set."
        default: code.hasPrefix("invalid_config") ? "The server rejected the config as invalid." : "The change was refused."
        }
    }
}

/// Talks to ci.forkhorizon.com's /api/ci/v2/projects/config (CI-Scope-Web project-config-ingress.ts).
/// Reads use the read-only token; changes use the admin login. A change that weakens protection also needs the
/// owner's Touch ID passkey signature on the website (see ProjectConfigClient+Approval.swift).
struct ProjectConfigClient {
    var baseURL = URL(string: "https://ci.forkhorizon.com/api/ci/v2/projects")!
    var session: URLSession = .shared
    var now: () -> Date = Date.init
    /// Shows the approval page to the owner; replaced in tests.
    var open: (URL) -> Void = { NSWorkspace.shared.open($0) }
    var pollInterval: Duration = .seconds(2)
    var approvalTimeout: Duration = .seconds(300)

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

    /// The server decides whether a change weakens protection; if it does, the owner signs it on the website first.
    func update(_ config: ProjectConfig, admin: (user: String, password: String)) async throws -> ProjectConfig {
        do {
            return try await put(config, admin: admin, approvalID: nil)
        } catch ProjectConfigError.server(_, "owner_approval_required") {
            return try await put(config, admin: admin, approvalID: try await approve(config, admin: admin))
        }
    }

    private func put(_ config: ProjectConfig, admin: (user: String, password: String), approvalID: String?) async throws -> ProjectConfig {
        var request = jsonRequest(url: configURL(query: []), method: "PUT", admin: admin)
        var body: [String: Any] = ["config": try JSONSerialization.jsonObject(with: try JSONEncoder().encode(config))]
        if let approvalID { body["approval"] = ["id": approvalID] }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try decodeConfig(try await send(request))
    }

    private func configURL(query: [URLQueryItem]) -> URL {
        var components = URLComponents(url: baseURL.appendingPathComponent("config"), resolvingAgainstBaseURL: false)!
        components.queryItems = query.isEmpty ? nil : query
        return components.url!
    }

    func jsonRequest(url: URL, method: String, admin: (user: String, password: String)) -> URLRequest {
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

    func send(_ request: URLRequest) async throws -> [String: Any] {
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
