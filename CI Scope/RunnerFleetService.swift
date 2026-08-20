import Foundation

struct RunnerFleetService {
    let config: DashboardConfig
    private let launchManager: V2AgentLaunchManager

    init(config: DashboardConfig = DashboardConfig()) {
        self.config = config
        self.launchManager = V2AgentLaunchManager(config: config)
    }

    func loadSnapshot() async -> RunnerFleetSnapshot {
        let launch = await launchManager.launchStatus()
        let v2Adapter = V2ClientStatusAdapter.configured()
        let v2Result = await v2Adapter?.status()

        let runner = runnerSnapshot(launch: launch, v2Result: v2Result)

        return RunnerFleetSnapshot(
            runners: [runner],
            refreshedAt: Date(),
            errors: [runner.error].compactMap { $0 }
        )
    }

    private func runnerSnapshot(
        launch: RunnerLaunchStatus,
        v2Result: V2ClientStatusResult?
    ) -> RunnerMonitorSnapshot {
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

        guard let v2Result else {
            snapshot.state = launch.state
            snapshot.localState = launch.state
            snapshot.githubState = .unknown
            snapshot.remoteName = "MacBook Agent (V2)"
            snapshot.remoteStatus = launch.state == .online ? "agent active" : "not running"
            snapshot.error = launch.state == .offline ? "V2 Agent launchd service is not running." : nil
            return snapshot
        }

        switch v2Result {
        case .available(let projection):
            let isOnline = projection.processAlive && projection.serverConnected
            snapshot.localState = projection.processAlive ? .online : .offline
            snapshot.githubState = projection.serverConnected ? .online : .offline
            snapshot.state = projection.readyToClaim ? .online : (isOnline ? .warning : .offline)
            snapshot.remoteName = "MacBook Agent (V2)"
            snapshot.remoteStatus = projection.readyToClaim ? "ready to claim" : (projection.draining ? "draining" : (projection.state ?? "connected"))
            snapshot.isBusy = projection.processAlive && !projection.readyToClaim && !projection.draining

            var errors: [String] = []
            if projection.recoveryBlocked {
                errors.append("Agent recovery is blocked.")
            }
            if projection.projectionLagging {
                errors.append("Control plane projection is lagging.")
            }
            snapshot.error = errors.joined(separator: "\n").nilIfEmpty

        case .unavailable(let error):
            snapshot.localState = launch.state
            snapshot.githubState = .offline
            snapshot.state = .warning
            snapshot.remoteName = "MacBook Agent (V2)"
            snapshot.remoteStatus = "socket unavailable"
            snapshot.error = error
        }

        return snapshot
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
