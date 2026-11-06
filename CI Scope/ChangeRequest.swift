// A pull request's change to protected files that waits for the owner's decision (the website Inbox).
import Combine
import Foundation

struct ChangeRequest: Codable, Equatable, Identifiable {
    struct Item: Codable, Equatable {
        var path: String
        var kind: String
        var fingerprint: String?
        var previous: String?
    }

    var id: Int
    var repository: String
    var pullRequest: Int?
    var headSha: String
    var items: [Item]
    var status: String
    var createdAt: Int

    var isPending: Bool { status == "pending" }
}

/// Talks to ci.forkhorizon.com's /api/ci/v2/site/changes and /api/ci/v2/changes/decide (admin Basic auth).
struct ChangeRequestsClient {
    var baseURL = URL(string: "https://ci.forkhorizon.com/api/ci/v2")!
    var session: URLSession = .shared

    func list(admin: (user: String, password: String)) async throws -> [ChangeRequest] {
        var request = URLRequest(url: baseURL.appendingPathComponent("site/changes"))
        authorize(&request, admin)
        let data = try await send(request)
        struct Reply: Decodable { var changes: [ChangeRequest] }
        do { return try JSONDecoder().decode(Reply.self, from: data).changes } catch { throw ProjectConfigError.malformedResponse }
    }

    /// Rejecting needs no signature; approving is signed with a passkey on the website, so the app never approves.
    func reject(id: Int, admin: (user: String, password: String)) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("changes/decide"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        authorize(&request, admin)
        request.httpBody = try JSONSerialization.data(withJSONObject: ["id": id, "decision": "reject"])
        _ = try await send(request)
    }

    private func authorize(_ request: inout URLRequest, _ admin: (user: String, password: String)) {
        request.setValue("Basic " + Data("\(admin.user):\(admin.password)".utf8).base64EncodedString(), forHTTPHeaderField: "authorization")
    }

    private func send(_ request: URLRequest) async throws -> Data {
        var request = request
        request.timeoutInterval = 30
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let code = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw ProjectConfigError.server(status: status, code: code ?? "unknown")
        }
        return data
    }
}

// ponytail: loads on demand (tab open, Refresh, after Reject) because every call needs the admin login; polling would prompt Touch ID.
@MainActor
final class ChangeRequestMonitor: ObservableObject {
    @Published private(set) var requests: [ChangeRequest] = []
    @Published var message: String?

    var client = ChangeRequestsClient()
    var adminLogin: (String) async throws -> (user: String, password: String) = { reason in
        try await ServerAuthorizer.adminLogin(reason: reason)
    }

    var pending: [ChangeRequest] { requests.filter(\.isPending) }

    /// Pending requests grouped by repository, repositories in alphabetical order.
    var pendingByRepository: [(repository: String, requests: [ChangeRequest])] {
        Dictionary(grouping: pending, by: \.repository).sorted { $0.key.lowercased() < $1.key.lowercased() }
            .map { (repository: $0.key, requests: $0.value.sorted { $0.createdAt < $1.createdAt }) }
    }

    func refresh() async {
        do {
            requests = try await client.list(admin: try await adminLogin("show protected-file change requests"))
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }

    func reject(_ request: ChangeRequest) async {
        do {
            try await client.reject(id: request.id, admin: try await adminLogin("reject the change to protected files in \(request.repository)"))
            await refresh()
        } catch {
            message = error.localizedDescription
        }
    }
}
