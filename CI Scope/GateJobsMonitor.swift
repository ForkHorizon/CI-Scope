// Keeps the agent's task list fresh while the Activity tab is open, and says when a new task arrives.
import Combine
import Foundation

@MainActor
final class GateJobsMonitor: ObservableObject {
    @Published private(set) var jobs: [GateJob] = []
    @Published private(set) var message: String?
    @Published private(set) var lastUpdated: Date?

    var client = GateJobsClient()
    var readToken: () async throws -> String = { try await ServerAuthorizer.configReadToken() }

    var activeCount: Int { jobs.filter(\.isActive).count }

    func refresh() async {
        do {
            jobs = try await client.fetch(readToken: try await readToken()).sorted { $0.updatedAt > $1.updatedAt }
            lastUpdated = Date()
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }
}
