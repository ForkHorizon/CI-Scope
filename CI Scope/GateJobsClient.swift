// Fetches the recent gate jobs (the agent's task list) from the CI Scope server.
import Foundation

struct GateJob: Decodable, Equatable, Identifiable {
    struct Report: Decodable, Equatable {
        var status: String
        var summary: String
        var completedAt: Int?
    }

    var id: String
    var repository: String
    var pullRequest: Int
    var headSha: String
    var status: String
    var attempts: Int
    var createdAt: Int
    var updatedAt: Int
    var report: Report?

    /// Queued, leased or running: the agent still owes this one an answer.
    var isActive: Bool { ["queued", "leased", "running"].contains(status) }

    var label: String {
        switch status {
        case "queued": "Waiting"
        case "leased", "running": "Running"
        case "succeeded": "Passed"
        case "failed": "Failed"
        case "cancelled": "Cancelled"
        default: status.capitalized
        }
    }
}

/// Talks to ci.forkhorizon.com's /api/ci/v2/local-gates/jobs (CI-Scope-Web local-gate-jobs-ingress.ts).
struct GateJobsClient {
    var url = URL(string: "https://ci.forkhorizon.com/api/ci/v2/local-gates/jobs")!
    var session: URLSession = .shared

    func fetch(readToken: String) async throws -> [GateJob] {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(readToken, forHTTPHeaderField: "x-ci-scope-config-token")
        let (data, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw GateJobsError.http(code) }
        struct Body: Decodable { var recent: [GateJob]? }
        return try JSONDecoder().decode(Body.self, from: data).recent ?? []
    }
}

enum GateJobsError: LocalizedError {
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .http(404): "The server has no task list yet (HTTP 404): it needs the newer CI-Scope-Web."
        case .http(let code): "The server answered the task list with HTTP \(code)."
        }
    }
}
