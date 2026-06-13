import Foundation

extension LocalBrokerService {
    func loadRunnerSnapshot(prepareBroker: Bool = true) async -> RunnerMonitorSnapshot {
        if prepareBroker {
            _ = try? await installOrUpdateLaunchAgent()
        }
        let registry = loadRegistry()
        let state = loadState()
        let launch = await launchStatus()
        let staleWarning = staleStateWarning(for: state, launch: launch)
        let profiles = registry.profiles.filter(\.enabled)
        let subRunners = profiles.map { profile in
            subRunnerSnapshot(profile: profile, registry: registry, state: state, launch: launch)
        }
        let activeJobs = state.activeJobs.map(\.workItem)
        let queuedJobs = state.queue.map(\.workItem)
        let visibleRepositoryCount = subRunners.reduce(0) { $0 + $1.visibleRepositoryCount }

        var snapshot = RunnerMonitorSnapshot(
            id: "local-mac-broker",
            title: "MacBook Runner",
            scope: "ForkHorizon organization + Daliys private repositories",
            root: brokerDirectory.path
        )
        snapshot.localState = launch.state
        snapshot.githubState = dispatcherState(launch: launch, state: state)
        snapshot.launchctlState = launch.launchctlState
        snapshot.pid = launch.pid
        snapshot.uptime = launch.uptime
        snapshot.serviceLabel = LocalBrokerConstants.serviceLabel
        snapshot.remoteName = "MacBook Controller"
        snapshot.remoteStatus = "parallel dispatcher"
        snapshot.registeredTo = "\(subRunners.count) sub-runners"
        snapshot.labels = uniqueLabels(profiles.flatMap(\.labels))
        snapshot.activeJobs = activeJobs
        snapshot.queuedJobs = queuedJobs
        snapshot.visibleRepositoryCount = visibleRepositoryCount
        snapshot.subRunners = subRunners
        snapshot.webhook = state.webhook
        snapshot.error = [state.lastError, staleWarning].compactMap { $0 }.joined(separator: "\n").nilIfEmpty
        snapshot.state = brokerState(launch: launch, state: state, subRunners: subRunners, staleWarning: staleWarning)
        return snapshot
    }

    private func subRunnerSnapshot(
        profile: BrokerRunnerProfile,
        registry: BrokerRegistry,
        state: BrokerState,
        launch: RunnerLaunchStatus
    ) -> RunnerSubRunnerSnapshot {
        let statuses = repositoryStatuses(for: profile, registry: registry, state: state)
        let activeJobCount = state.activeJobs.filter { jobMatchesProfile($0, profile: profile) }.count
        let queuedJobCount = state.queue.filter { jobMatchesProfile($0, profile: profile) }.count
        let visibleRepositoryCount = visibleRepositoryCount(for: profile, registry: registry, statuses: statuses)
        let lastError = subRunnerLastError(statuses: statuses)
        let runnerState = subRunnerState(
            launch: launch,
            statuses: statuses,
            activeJobCount: activeJobCount,
            queuedJobCount: queuedJobCount,
            lastError: lastError
        )

        return RunnerSubRunnerSnapshot(
            id: profile.id,
            title: profile.title,
            scope: profile.scope,
            labels: profile.labels,
            state: runnerState,
            visibleRepositoryCount: visibleRepositoryCount,
            queuedJobCount: queuedJobCount,
            activeJobCount: activeJobCount,
            lastError: lastError
        )
    }

    private func repositoryStatuses(
        for profile: BrokerRunnerProfile,
        registry: BrokerRegistry,
        state: BrokerState
    ) -> [BrokerRepoStatus] {
        state.repos.filter { repoStatus in
            if let profileID = repoStatus.profileID {
                return profileID == profile.id
            }

            guard profile.kind == .privateRepositories else { return false }
            return registry.repos.contains {
                $0.slug.caseInsensitiveCompare(repoStatus.slug) == .orderedSame
            }
        }
    }

    private func visibleRepositoryCount(
        for profile: BrokerRunnerProfile,
        registry: BrokerRegistry,
        statuses: [BrokerRepoStatus]
    ) -> Int {
        switch profile.kind {
        case .organization:
            return statuses.count
        case .privateRepositories:
            return max(registry.repos.filter(\.enabled).count, statuses.count)
        }
    }

    private func subRunnerLastError(statuses: [BrokerRepoStatus]) -> String? {
        let statusErrors = statuses.compactMap { status -> String? in
            guard let error = status.lastError, !error.isEmpty else { return nil }
            return "\(status.slug): \(error)"
        }
        return statusErrors.joined(separator: "\n").nilIfEmpty
    }

    private func subRunnerState(
        launch: RunnerLaunchStatus,
        statuses: [BrokerRepoStatus],
        activeJobCount: Int,
        queuedJobCount: Int,
        lastError: String?
    ) -> ServiceState {
        if launch.state == .offline { return .offline }
        if lastError != nil || activeJobCount > 0 || queuedJobCount > 0 { return .warning }
        if statuses.contains(where: { $0.state.lowercased() == "warning" }) { return .warning }
        return launch.state
    }

    private func launchStatus() async -> RunnerLaunchStatus {
        let result = await ShellClient.run(
            "launchctl print gui/\(geteuid())/\(LocalBrokerConstants.serviceLabel)",
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

    private func brokerState(
        launch: RunnerLaunchStatus,
        state: BrokerState,
        subRunners: [RunnerSubRunnerSnapshot],
        staleWarning: String?
    ) -> ServiceState {
        if launch.state == .offline { return .offline }
        if subRunners.contains(where: { $0.state == .offline }) { return .offline }
        if state.lastError != nil || staleWarning != nil || !state.activeJobs.isEmpty || !state.queue.isEmpty { return .warning }
        if subRunners.contains(where: { $0.state == .warning }) { return .warning }
        return launch.state
    }

    private func dispatcherState(launch: RunnerLaunchStatus, state: BrokerState) -> ServiceState {
        if launch.state == .offline { return .offline }
        if state.lastError != nil { return .warning }
        return launch.state
    }

    private func staleStateWarning(for state: BrokerState, launch: RunnerLaunchStatus) -> String? {
        guard launch.state != .offline else { return nil }
        guard !state.updatedAt.isEmpty else {
            return "Broker state has not been written yet."
        }
        guard let updatedAt = brokerStateDate(from: state.updatedAt) else {
            return "Broker state timestamp is not readable."
        }

        let age = Date().timeIntervalSince(updatedAt)
        guard age > LocalBrokerConstants.stateStaleAfterSeconds else { return nil }
        return "Broker state is stale. Last update was \(Int(age))s ago."
    }

    private func brokerStateDate(from value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private func jobMatchesProfile(_ job: BrokerJob, profile: BrokerRunnerProfile) -> Bool {
        if let profileID = job.profileID {
            return profileID == profile.id
        }

        let availableLabels = Set(job.labels.map { $0.lowercased() })
        return profile.labels.allSatisfy { availableLabels.contains($0.lowercased()) }
    }

    private func uniqueLabels(_ labels: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for label in labels {
            let key = label.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(label)
        }
        return result
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

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
