import Foundation

/// Recent workflow runs/jobs that the broker recorded from GitHub webhook
/// deliveries (workflow-runs.json). Reading this lets the dashboard render run
/// status with zero GitHub API calls; a direct `gh` query is only a cold-start
/// or broker-down fallback.
struct WorkflowRunsFeed: Decodable {
    let updatedAt: String?
    let runs: [Run]

    struct Run: Decodable {
        let id: Int
        let repositorySlug: String
        let workflowName: String
        let displayTitle: String
        let headBranch: String
        let status: String
        let conclusion: String?
        let url: String
        let event: String?
        let createdAt: String
        let updatedAt: String?
        let jobs: [Job]?
    }

    struct Job: Decodable {
        let id: Int
        let name: String
        let status: String
        let conclusion: String?
        let runnerName: String?
        let htmlURL: String?
        let startedAt: String?
        let completedAt: String?
        let labels: [String]?
    }
}

extension WorkflowRunsFeed {
    func githubRuns(forRepositorySlug slug: String, limit: Int = 20) -> [GitHubRun] {
        runs
            .filter { $0.repositorySlug.caseInsensitiveCompare(slug) == .orderedSame }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(limit)
            .map { $0.asGitHubRun() }
    }
}

extension WorkflowRunsFeed.Run {
    /// Maps a feed run onto the dashboard's GitHubRun model.
    func asGitHubRun() -> GitHubRun {
        GitHubRun(
            databaseId: id,
            status: status,
            conclusion: conclusion,
            displayTitle: displayTitle,
            workflowName: workflowName,
            headBranch: headBranch,
            event: event ?? "",
            createdAt: createdAt,
            updatedAt: updatedAt ?? createdAt,
            url: url
        )
    }
}

extension LocalBrokerService {
    func workflowRunsFeed(maxAge: TimeInterval = 900) -> WorkflowRunsFeed? {
        guard isWorkflowRunsFeedFresh(maxAge: maxAge),
            let data = try? Data(contentsOf: workflowRunsURL),
            let feed = try? JSONDecoder().decode(WorkflowRunsFeed.self, from: data)
        else { return nil }
        return feed
    }

    private func isWorkflowRunsFeedFresh(maxAge: TimeInterval) -> Bool {
        guard let attributes = try? fileManager.attributesOfItem(atPath: workflowRunsURL.path),
            let modified = attributes[.modificationDate] as? Date
        else { return false }
        return Date().timeIntervalSince(modified) <= maxAge
    }
}
