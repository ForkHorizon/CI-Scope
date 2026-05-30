import Foundation

struct RunnerFleetService {
    let config: DashboardConfig

    func loadSnapshot() async -> RunnerFleetSnapshot {
        let indexed = await withTaskGroup(of: (Int, RunnerMonitorSnapshot).self) { group in
            for pair in config.actionsRunners.enumerated() {
                group.addTask {
                    let runner = await loadRunner(pair.element)
                    return (pair.offset, runner)
                }
            }

            var results: [(Int, RunnerMonitorSnapshot)] = []
            for await result in group {
                results.append(result)
            }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }

        return RunnerFleetSnapshot(
            runners: indexed,
            refreshedAt: Date(),
            errors: indexed.compactMap(\.error)
        )
    }

    private func loadRunner(_ runnerConfig: ActionsRunnerConfig) async -> RunnerMonitorSnapshot {
        var snapshot = RunnerMonitorSnapshot(
            id: runnerConfig.id,
            title: runnerConfig.title,
            scope: runnerConfig.scope.description,
            root: runnerConfig.root
        )

        let localRunner = readLocalRunner(runnerConfig)
        snapshot.registeredTo = localRunner?.registrationLabel ?? "Not registered"
        snapshot.remoteName = localRunner?.runner.agentName ?? "-"
        snapshot.serviceLabel = serviceLabel(for: runnerConfig)

        let launch = await localLaunchStatus(serviceLabel: snapshot.serviceLabel, title: runnerConfig.title)
        snapshot.localState = launch.state
        snapshot.launchctlState = launch.launchctlState
        snapshot.pid = launch.pid
        snapshot.uptime = launch.uptime
        snapshot.error = launch.error

        let remoteResult = await remoteRunner(for: runnerConfig, localRunner: localRunner)
        applyRemoteStatus(remoteResult, runnerConfig: runnerConfig, snapshot: &snapshot)
        let jobs = await repositoryJobs(for: runnerConfig, localRunner: localRunner, runnerName: snapshot.remoteName)
        snapshot.visibleRepositoryCount = jobs.visibleRepositoryCount
        snapshot.activeJobs = jobs.active
        snapshot.queuedJobs = jobs.queued

        snapshot.state = state(for: snapshot)
        return snapshot
    }

    private func applyRemoteStatus(
        _ remoteResult: FleetLoadResponse<FleetGitHubActionsRunner>,
        runnerConfig: ActionsRunnerConfig,
        snapshot: inout RunnerMonitorSnapshot
    ) {
        guard let remote = remoteResult.value else {
            snapshot.githubState = .unknown
            snapshot.missingLabels = runnerConfig.requiredLabels
            snapshot.error = [snapshot.error, remoteResult.error]
                .compactMap { $0 }
                .joined(separator: "\n")
                .nilIfEmpty
            return
        }

        snapshot.githubState = remote.status.lowercased() == "online" ? .online : .offline
        snapshot.remoteName = remote.name
        snapshot.remoteStatus = remote.status
        snapshot.isBusy = remote.busy
        snapshot.labels = remote.labels.map(\.name).sorted()
        snapshot.missingLabels = missingLabels(for: runnerConfig, remoteRunner: remote)
    }

    private func repositoryJobs(
        for runnerConfig: ActionsRunnerConfig,
        localRunner: FleetLocalRunnerInfo?,
        runnerName: String
    ) async -> (visibleRepositoryCount: Int, active: [RunnerWorkItem], queued: [RunnerWorkItem]) {
        let repositories = await repositoriesVisibleToRunner(runnerConfig, localRunner: localRunner)
        let active = await activeJobs(
            repositories: repositories,
            runnerName: runnerName,
            requiredLabels: runnerConfig.requiredLabels
        )
        let queued = await queuedJobs(repositories: repositories, requiredLabels: runnerConfig.requiredLabels)
        return (repositories.count, active, queued)
    }

    private func state(for snapshot: RunnerMonitorSnapshot) -> ServiceState {
        if snapshot.localState == .offline || snapshot.githubState == .offline { return .offline }
        if !snapshot.missingLabels.isEmpty || snapshot.isBusy || !snapshot.activeJobs.isEmpty { return .warning }
        if snapshot.localState == .online && snapshot.githubState == .online { return .online }
        return .unknown
    }

    private func activeJobs(
        repositories: [String],
        runnerName: String,
        requiredLabels: [String]
    ) async -> [RunnerWorkItem] {
        guard runnerName != "-" else { return [] }
        let runs = await workflowRuns(repositories: repositories, status: "in_progress")
        let jobs = await jobs(for: runs)

        return jobs.compactMap { context in
            guard
                context.job.runnerName?.caseInsensitiveCompare(runnerName) == .orderedSame,
                context.job.status != "completed"
            else { return nil }

            return workItem(for: context.run, job: context.job, requiredLabels: requiredLabels)
        }
    }

    private func queuedJobs(repositories: [String], requiredLabels: [String]) async -> [RunnerWorkItem] {
        let runs = await workflowRuns(repositories: repositories, status: "queued")
        let jobs = await jobs(for: runs)
        let matchedJobs = jobs.compactMap { context -> RunnerWorkItem? in
            guard hasLabels(context.job.labels, requiredLabels: requiredLabels) else { return nil }
            return workItem(for: context.run, job: context.job, requiredLabels: requiredLabels)
        }

        if !matchedJobs.isEmpty {
            return matchedJobs
        }

        return runs.map { run in
            RunnerWorkItem(
                id: "\(run.repositorySlug):\(run.id):queued-run",
                repositorySlug: run.repositorySlug,
                workflowName: run.workflowName,
                title: run.displayTitle,
                jobName: "Queued run",
                headBranch: run.headBranch,
                status: run.status,
                url: run.url,
                createdAt: run.createdAt,
                labels: requiredLabels
            )
        }
    }

    private func workItem(
        for run: WorkflowRunContext,
        job: WorkflowJob,
        requiredLabels: [String]
    ) -> RunnerWorkItem {
        RunnerWorkItem(
            id: "\(run.repositorySlug):\(run.id):\(job.id)",
            repositorySlug: run.repositorySlug,
            workflowName: job.workflowName ?? run.workflowName,
            title: run.displayTitle,
            jobName: job.name,
            headBranch: run.headBranch,
            status: job.status,
            url: job.htmlURL ?? run.url,
            createdAt: job.startedAt ?? job.createdAt ?? run.createdAt,
            labels: job.labels.isEmpty ? requiredLabels : job.labels
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
