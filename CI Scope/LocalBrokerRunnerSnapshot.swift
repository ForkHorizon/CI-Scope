import Foundation

extension LocalBrokerService {
    func loadRunnerSnapshot() async -> RunnerMonitorSnapshot {
        _ = try? await installOrUpdateLaunchAgent()
        let registry = loadRegistry()
        let state = loadState()
        let launch = await launchStatus()

        var snapshot = RunnerMonitorSnapshot(
            id: "local-mac-broker",
            title: "Local Mac Broker",
            scope: "Daliys private repositories",
            root: brokerDirectory.path
        )
        snapshot.localState = launch.state
        snapshot.githubState = state.lastError == nil ? .online : .warning
        snapshot.launchctlState = launch.launchctlState
        snapshot.pid = launch.pid
        snapshot.uptime = launch.uptime
        snapshot.serviceLabel = LocalBrokerConstants.serviceLabel
        snapshot.remoteName = "JIT runners"
        snapshot.remoteStatus = "managed"
        snapshot.registeredTo = "\(registry.repos.filter(\.enabled).count) managed repos"
        snapshot.labels = LocalBrokerConstants.runnerLabels
        snapshot.activeJobs = state.active.map { [$0.workItem] } ?? []
        snapshot.queuedJobs = state.queue.map(\.workItem)
        snapshot.visibleRepositoryCount = registry.repos.filter(\.enabled).count
        snapshot.error = state.lastError
        snapshot.state = brokerState(launch: launch, state: state)
        return snapshot
    }

    private func launchStatus() async -> RunnerLaunchStatus {
        let result = await ShellClient.run(
            "launchctl print gui/$(id -u)/\(LocalBrokerConstants.serviceLabel)",
            timeout: 5,
            config: config
        )
        guard result.exitCode == 0 else {
            return RunnerLaunchStatus(
                state: .offline,
                launchctlState: "not running",
                pid: nil,
                uptime: "-",
                error: result.output.trimmed
            )
        }

        let launchState = firstMatch(in: result.output, pattern: #"state = ([a-zA-Z]+)"#) ?? "running"
        let pid = intMatch(in: result.output, pattern: #"pid = ([0-9]+)"#)
        return RunnerLaunchStatus(
            state: launchState == "running" ? .online : .warning,
            launchctlState: launchState,
            pid: pid,
            uptime: await processUptime(pid: pid),
            error: nil
        )
    }

    private func brokerState(launch: RunnerLaunchStatus, state: BrokerState) -> ServiceState {
        if launch.state == .offline { return .offline }
        if state.lastError != nil || state.active != nil || !state.queue.isEmpty { return .warning }
        return launch.state
    }

    private func processUptime(pid: Int?) async -> String {
        guard let pid else { return "-" }
        let result = await ShellClient.run("ps -p \(pid) -o etime= | xargs", timeout: 3, config: config)
        let uptime = result.output.trimmed
        return uptime.isEmpty ? "-" : uptime
    }

    private func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1 else { return nil }
        guard let valueRange = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[valueRange])
    }

    private func intMatch(in text: String, pattern: String) -> Int? {
        firstMatch(in: text, pattern: pattern).flatMap(Int.init)
    }
}
