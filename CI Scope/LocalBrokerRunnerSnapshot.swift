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
        let activeJobs = state.active.map { [$0.workItem] } ?? []
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
        snapshot.remoteStatus = "serial dispatcher"
        snapshot.registeredTo = "\(subRunners.count) sub-runners"
        snapshot.labels = uniqueLabels(profiles.flatMap(\.labels))
        snapshot.activeJobs = activeJobs
        snapshot.queuedJobs = queuedJobs
        snapshot.visibleRepositoryCount = visibleRepositoryCount
        snapshot.subRunners = subRunners
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
        let statuses = state.repos.filter { repoStatus in
            if let profileID = repoStatus.profileID {
                return profileID == profile.id
            }

            guard profile.kind == .privateRepositories else { return false }
            return registry.repos.contains {
                $0.slug.caseInsensitiveCompare(repoStatus.slug) == .orderedSame
            }
        }
        let activeJobCount = state.active.map { jobMatchesProfile($0, profile: profile) ? 1 : 0 } ?? 0
        let queuedJobCount = state.queue.filter { jobMatchesProfile($0, profile: profile) }.count
        let visibleRepositoryCount: Int
        switch profile.kind {
        case .organization:
            visibleRepositoryCount = statuses.count
        case .privateRepositories:
            visibleRepositoryCount = max(registry.repos.filter(\.enabled).count, statuses.count)
        }
        let statusErrors = statuses.compactMap { status -> String? in
            guard let error = status.lastError, !error.isEmpty else { return nil }
            return "\(status.slug): \(error)"
        }
        let lastError = statusErrors.joined(separator: "\n").nilIfEmpty
        let state: ServiceState =
            if launch.state == .offline {
                .offline
            } else if lastError != nil || activeJobCount > 0 || queuedJobCount > 0
                || statuses.contains(where: { $0.state.lowercased() == "warning" }) {
                .warning
            } else {
                launch.state
            }

        return RunnerSubRunnerSnapshot(
            id: profile.id,
            title: profile.title,
            scope: profile.scope,
            labels: profile.labels,
            state: state,
            visibleRepositoryCount: visibleRepositoryCount,
            queuedJobCount: queuedJobCount,
            activeJobCount: activeJobCount,
            lastError: lastError
        )
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

    private func brokerState(
        launch: RunnerLaunchStatus,
        state: BrokerState,
        subRunners: [RunnerSubRunnerSnapshot],
        staleWarning: String?
    ) -> ServiceState {
        if launch.state == .offline { return .offline }
        if subRunners.contains(where: { $0.state == .offline }) { return .offline }
        if state.lastError != nil || staleWarning != nil || state.active != nil || !state.queue.isEmpty { return .warning }
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
