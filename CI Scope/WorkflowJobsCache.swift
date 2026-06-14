import Foundation

/// Caches jobs for runs that have reached a terminal state. A completed run's
/// jobs never change, so once fetched they can be reused indefinitely — letting
/// the dashboard skip the per-run `gh api .../jobs` call (the single largest
/// source of requests per refresh). In-progress and queued runs are never
/// cached, so their jobs are always re-fetched.
actor WorkflowJobsCache {
    static let shared = WorkflowJobsCache()

    private var entries: [Int64: [JobContext]] = [:]
    private var order: [Int64] = []
    private let maxEntries = 300

    /// Cached jobs for a run, but only if the run is in a terminal state.
    func jobs(for run: WorkflowRunContext) -> [JobContext]? {
        guard Self.isTerminal(run) else { return nil }
        return entries[run.id]
    }

    /// Stores jobs for a run if it is terminal; no-op otherwise.
    func store(_ jobs: [JobContext], for run: WorkflowRunContext) {
        guard Self.isTerminal(run) else { return }
        if entries[run.id] == nil { order.append(run.id) }
        entries[run.id] = jobs
        evictIfNeeded()
    }

    private func evictIfNeeded() {
        while order.count > maxEntries {
            let evicted = order.removeFirst()
            entries.removeValue(forKey: evicted)
        }
    }

    private static func isTerminal(_ run: WorkflowRunContext) -> Bool {
        run.status == "completed"
    }
}
