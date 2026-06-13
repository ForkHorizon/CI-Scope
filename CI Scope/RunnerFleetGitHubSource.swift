import Foundation

extension RunnerFleetService {
    func repositoriesVisibleToRunner(
        _ runnerConfig: ActionsRunnerConfig,
        localRunner: FleetLocalRunnerInfo?
    ) async -> [String] {
        switch runnerConfig.scope {
        case .organization(let organization):
            if await GitHubRateLimitGate.shared.isPaused() { return [] }
            let command = """
            gh repo list \(quoted(organization)) --limit 200 --json nameWithOwner,isArchived \
            --jq '[.[] | select(.isArchived == false) | .nameWithOwner]'
            """
            let result = await ShellClient.run(command, timeout: 20, config: config)
            await GitHubRateLimitGate.shared.note(result: result, config: config)
            guard
                result.exitCode == 0,
                let data = result.output.data(using: .utf8),
                let repositories = try? JSONDecoder().decode([String].self, from: data)
            else {
                return []
            }
            return repositories

        case .personalAccount, .repository:
            return localRunner?.repositorySlug.map { [$0] } ?? []
        }
    }

    func remoteRunner(
        for runnerConfig: ActionsRunnerConfig,
        localRunner: FleetLocalRunnerInfo?
    ) async -> FleetLoadResponse<FleetGitHubActionsRunner> {
        if await GitHubRateLimitGate.shared.isPaused() {
            return FleetLoadResponse(error: "Paused: GitHub rate limit reached.")
        }
        let command: String
        switch runnerConfig.scope {
        case .organization(let organization):
            command = "gh api --cache 30s \(quoted("orgs/\(organization)/actions/runners"))"
        case .personalAccount, .repository:
            guard let repositorySlug = localRunner?.repositorySlug else {
                return FleetLoadResponse(error: "Local runner is not registered to a GitHub repository.")
            }
            command = "gh api --cache 30s \(quoted("repos/\(repositorySlug)/actions/runners"))"
        }

        let result = await ShellClient.run(command, timeout: 15, config: config)
        await GitHubRateLimitGate.shared.note(result: result, config: config)
        guard result.exitCode == 0, let data = result.output.data(using: .utf8) else {
            return FleetLoadResponse(error: trimmedError(result.output, fallback: "Could not read GitHub runner status."))
        }

        guard let list = try? JSONDecoder().decode(FleetGitHubRunnerList.self, from: data) else {
            return FleetLoadResponse(error: "Could not parse GitHub runner status.")
        }

        if let agentName = localRunner?.runner.agentName,
           let runner = list.runners.first(where: { $0.name.caseInsensitiveCompare(agentName) == .orderedSame }) {
            return FleetLoadResponse(value: runner)
        }

        if let runner = list.runners.first(where: { $0.hasLabels(runnerConfig.requiredLabels) }) {
            return FleetLoadResponse(value: runner)
        }

        return FleetLoadResponse(error: "No GitHub runner matches \(runnerConfig.title).")
    }

    func workflowRuns(repositories: [String], status: String) async -> [WorkflowRunContext] {
        let runs = await mapConcurrently(repositories, maxConcurrent: 4) { repository in
            await workflowRuns(repository: repository, status: status)
        }
        return runs.flatMap { $0 }.sorted { $0.createdAt > $1.createdAt }
    }

    func jobs(for runs: [WorkflowRunContext]) async -> [JobContext] {
        var cached: [JobContext] = []
        var pending: [WorkflowRunContext] = []
        for run in runs {
            if let hit = await WorkflowJobsCache.shared.jobs(for: run) {
                cached.append(contentsOf: hit)
            } else {
                pending.append(run)
            }
        }

        let fetched = await mapConcurrently(pending, maxConcurrent: 4) { run in
            await jobs(for: run)
        }
        return cached + fetched.flatMap { $0 }
    }

    private func workflowRuns(repository: String, status: String) async -> [WorkflowRunContext] {
        if await GitHubRateLimitGate.shared.isPaused() { return [] }
        let command = "gh api --cache 30s \(quoted("repos/\(repository)/actions/runs?status=\(status)&per_page=20"))"
        let result = await ShellClient.run(command, timeout: 15, config: config)
        await GitHubRateLimitGate.shared.note(result: result, config: config)
        guard result.exitCode == 0, let data = result.output.data(using: .utf8) else {
            return []
        }

        guard let decoded = try? JSONDecoder().decode(WorkflowRunList.self, from: data) else {
            return []
        }

        return decoded.workflowRuns.map { run in
            WorkflowRunContext(
                id: run.id,
                repositorySlug: repository,
                workflowName: run.name ?? "Workflow",
                displayTitle: run.displayTitle ?? run.name ?? "Workflow run",
                headBranch: run.headBranch ?? "-",
                status: run.status,
                conclusion: run.conclusion,
                url: run.htmlURL ?? "",
                createdAt: run.createdAt ?? ""
            )
        }
    }

    private func jobs(for run: WorkflowRunContext) async -> [JobContext] {
        if await GitHubRateLimitGate.shared.isPaused() {
            return await WorkflowJobsCache.shared.jobs(for: run) ?? []
        }
        let command = "gh api --cache 30s \(quoted("repos/\(run.repositorySlug)/actions/runs/\(run.id)/jobs?per_page=100"))"
        let result = await ShellClient.run(command, timeout: 15, config: config)
        await GitHubRateLimitGate.shared.note(result: result, config: config)
        guard result.exitCode == 0, let data = result.output.data(using: .utf8) else {
            return []
        }

        guard let decoded = try? JSONDecoder().decode(WorkflowJobList.self, from: data) else {
            return []
        }

        let jobs = decoded.jobs.map { JobContext(run: run, job: $0) }
        await WorkflowJobsCache.shared.store(jobs, for: run)
        return jobs
    }
}

private struct WorkflowRunList: Decodable {
    let workflowRuns: [WorkflowRun]

    private enum CodingKeys: String, CodingKey {
        case workflowRuns = "workflow_runs"
    }
}

private struct WorkflowRun: Decodable {
    let id: Int64
    let name: String?
    let displayTitle: String?
    let headBranch: String?
    let status: String
    let conclusion: String?
    let htmlURL: String?
    let createdAt: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case displayTitle = "display_title"
        case headBranch = "head_branch"
        case status
        case conclusion
        case htmlURL = "html_url"
        case createdAt = "created_at"
    }
}

private struct WorkflowJobList: Decodable {
    let jobs: [WorkflowJob]
}
