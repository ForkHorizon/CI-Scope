import Foundation

struct RunnerFleetService {
  let config: DashboardConfig
  private let launchManager: V2AgentLaunchManager

  init(config: DashboardConfig = DashboardConfig()) {
    self.config = config
    self.launchManager = V2AgentLaunchManager(config: config)
  }

  func loadSnapshot(projects: [CIProject]? = nil) async -> RunnerFleetSnapshot {
    let launch = await launchManager.launchStatus()
    let v2Adapter = V2ClientStatusAdapter.configured()
    let v2Result = await v2Adapter?.status()

    let projectList =
      (projects?.isEmpty == false ? projects : nil) ?? ProjectStore.loadConfiguredProjects()
    let (activeJobs, queuedJobs) = await loadFleetJobs(for: projectList)

    var runner = runnerSnapshot(launch: launch, v2Result: v2Result)
    runner.activeJobs = activeJobs
    runner.queuedJobs = queuedJobs
    if !activeJobs.isEmpty {
      runner.isBusy = true
    }

    return RunnerFleetSnapshot(
      runners: [runner],
      refreshedAt: Date(),
      errors: [runner.error].compactMap { $0 }
    )
  }

  private func loadFleetJobs(for projects: [CIProject]) async -> (
    active: [RunnerWorkItem], queued: [RunnerWorkItem]
  ) {
    guard !projects.isEmpty else { return ([], []) }
    let ciService = ProjectCIService(config: config)
    var active: [RunnerWorkItem] = []
    var queued: [RunnerWorkItem] = []

    await withTaskGroup(of: (CIProject, [GitHubRun]).self) { group in
      for project in projects {
        group.addTask {
          let response = await ciService.loadRuns(for: project)
          return (project, response.value ?? [])
        }
      }

      for await (project, runs) in group {
        for run in runs {
          let item = RunnerWorkItem(
            id: String(run.databaseId),
            repositorySlug: project.repositorySlug,
            workflowName: run.workflowName,
            title: run.displayTitle,
            jobName: run.workflowName,
            headBranch: run.headBranch,
            status: run.status,
            url: run.url,
            assemblerTitle: nil,
            assemblerScope: nil,
            progress: nil
          )
          if run.status == "in_progress" {
            active.append(item)
          } else if run.status == "queued" {
            queued.append(item)
          }
        }
      }
    }

    return (active, queued)
  }

  private func runnerSnapshot(
    launch: RunnerLaunchStatus,
    v2Result: V2ClientStatusResult?
  ) -> RunnerMonitorSnapshot {
    var snapshot = initialRunnerSnapshot(launch: launch)
    guard let v2Result else {
      applyMissingV2(launch: launch, to: &snapshot)
      return snapshot
    }
    applyV2Result(v2Result, launch: launch, to: &snapshot)
    return snapshot
  }

  private func initialRunnerSnapshot(launch: RunnerLaunchStatus) -> RunnerMonitorSnapshot {
    var snapshot = RunnerMonitorSnapshot(
      id: "v2-mac-agent",
      title: "MacBook Runner",
      scope: "ForkHorizon organization + V2 Pool"
    )
    snapshot.launchctlState = launch.launchctlState
    snapshot.pid = launch.pid
    snapshot.uptime = launch.uptime
    snapshot.labels = ["self-hosted", "macOS", "ARM64", "ci-scope", "ci-scope-v2"]
    snapshot.registeredTo = "V2 Control Plane (VPS)"
    return snapshot
  }

  private func applyMissingV2(launch: RunnerLaunchStatus, to snapshot: inout RunnerMonitorSnapshot)
  {
    snapshot.state = launch.state
    snapshot.localState = launch.state
    snapshot.githubState = .unknown
    snapshot.remoteName = "MacBook Agent (V2)"
    snapshot.remoteStatus = launch.state == .online ? "agent active" : "not running"
    snapshot.error = launch.state == .offline ? "V2 Agent launchd service is not running." : nil
  }

  private func applyV2Result(
    _ v2Result: V2ClientStatusResult,
    launch: RunnerLaunchStatus,
    to snapshot: inout RunnerMonitorSnapshot
  ) {
    snapshot.remoteName = "MacBook Agent (V2)"
    switch v2Result {
    case .available(let projection):
      let isOnline = projection.processAlive && projection.serverConnected
      snapshot.localState = projection.processAlive ? .online : .offline
      snapshot.githubState = projection.serverConnected ? .online : .offline
      snapshot.state = projection.readyToClaim ? .online : (isOnline ? .warning : .offline)
      snapshot.remoteStatus =
        projection.readyToClaim
        ? "ready to claim" : (projection.draining ? "draining" : (projection.state ?? "connected"))
      snapshot.isBusy = projection.processAlive && !projection.readyToClaim && !projection.draining

      var errors: [String] = []
      if projection.recoveryBlocked { errors.append("Agent recovery is blocked.") }
      if projection.projectionLagging { errors.append("Control plane projection is lagging.") }
      snapshot.error = errors.joined(separator: "\n").nilIfEmpty

    case .unavailable(let error):
      snapshot.localState = launch.state
      snapshot.githubState = .offline
      snapshot.state = .warning
      snapshot.remoteStatus = "socket unavailable"
      snapshot.error = error
    }
  }
}

extension String {
  fileprivate var nilIfEmpty: String? {
    isEmpty ? nil : self
  }
}
