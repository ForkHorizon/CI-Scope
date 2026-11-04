// Keeps the agent's task list fresh and raises a toast when a check is queued, starts, or finishes.
import Combine
import Foundation

@MainActor
final class GateJobsMonitor: ObservableObject {
    @Published private(set) var jobs: [GateJob] = []
    @Published private(set) var message: String?
    @Published private(set) var lastUpdated: Date?

    var client = GateJobsClient()
    var readToken: () async throws -> String = { try await ServerAuthorizer.configReadToken() }

    /// Called for each job that is new or changed status since the last poll; `previous` is nil for a new job.
    var notify: (GateJob, _ previous: String?) -> Void = GateJobsMonitor.toast

    private var lastStatus: [String: String]?

    var activeCount: Int { jobs.filter(\.isActive).count }

    func refresh() async {
        do {
            jobs = try await client.fetch(readToken: try await readToken()).sorted { $0.updatedAt > $1.updatedAt }
            // The first successful poll only records what is already there, so launching the app is quiet.
            if let last = lastStatus {
                for job in jobs.reversed() where last[job.id] != job.status { notify(job, last[job.id]) }
            }
            lastStatus = Dictionary(jobs.map { ($0.id, $0.status) }, uniquingKeysWith: { first, _ in first })
            lastUpdated = Date()
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }

    /// Turns a job change into a card; statuses nobody needs to hear about (cancelled, ...) stay silent.
    static func toast(_ job: GateJob, previous: String?) {
        let title = "\(job.repository) #\(job.pullRequest)"
        let sha = String(job.headSha.prefix(7))
        let kind: Toast.Kind
        let detail: String
        switch job.status {
        case "queued":
            kind = .queued
            detail = previous == nil ? "New pull request check · \(sha)" : "Waiting for the agent · \(sha)"
        case "leased", "running":
            guard previous == nil || previous == "queued" else { return }
            kind = .running
            detail = "Check started on this Mac · \(sha)"
        case "succeeded":
            kind = .passed
            detail = job.report?.summary.isEmpty == false ? job.report!.summary : "All checks passed · \(sha)"
        case "failed":
            kind = .failed
            detail = job.report?.summary.isEmpty == false ? job.report!.summary : "Check failed · \(sha)"
        default:
            return
        }
        ToastCenter.shared.post(Toast(kind: kind, title: title, detail: detail, destination: .activity))
    }
}
