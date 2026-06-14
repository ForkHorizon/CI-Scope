import Foundation

extension ProjectCIService {
    func loadLocalRunner(for project: CIProject, prepareBroker: Bool = true) async -> ProjectLocalRunnerStatus {
        if LocalBrokerService(config: config).isManaged(project: project) {
            return await brokerRunnerStatus(for: project, prepareBroker: prepareBroker)
        }

        let localRunners = config.actionsRunners.compactMap(readLocalRunner)
        if let runner = localRunners.first(where: { localRunner($0, appliesTo: project) }) {
            return await localRunnerStatus(runner, for: project)
        }

        return await repositoryRunnerStatus(
            for: project,
            localRunners: localRunners
        )
    }

    func brokerRunnerStatus(for project: CIProject, prepareBroker: Bool = true) async -> ProjectLocalRunnerStatus {
        let broker = await LocalBrokerService(config: config).loadRunnerSnapshot(prepareBroker: prepareBroker)
        let active = broker.activeJobs.first { $0.repositorySlug.caseInsensitiveCompare(project.repositorySlug) == .orderedSame }
        let queued = broker.queuedJobs.filter { $0.repositorySlug.caseInsensitiveCompare(project.repositorySlug) == .orderedSame }
        let summary =
            if active != nil {
                "Running locally"
            } else if !queued.isEmpty {
                "Waiting for broker"
            } else {
                "Broker managed"
            }
        let detail = active?.title ?? (queued.first?.title ?? "MacBook Runner · \(broker.uptime)")

        return ProjectLocalRunnerStatus(
            state: broker.state,
            summary: summary,
            detail: detail,
            repositorySlug: project.repositorySlug,
            pid: broker.pid,
            filePath: LocalBrokerService(config: config).registryURL.path
        )
    }

    func repositoryRunnerStatus(
        for project: CIProject,
        localRunners: [LocalRunnerInfo]
    ) async -> ProjectLocalRunnerStatus {
        let response = await repositoryRunners(for: project)
        guard let runners = response.value else {
            return unknownRepositoryRunnerStatus(
                detail: response.error ?? "Could not read repo runners.",
                localRunners: localRunners
            )
        }

        let macRunners = runners.filter { $0.hasLabels(config.actionsRunnerRequiredLabels) }
        guard !macRunners.isEmpty else {
            return ProjectLocalRunnerStatus(
                state: .offline,
                summary: "No CI runner",
                detail: missingRunnerDetail(for: project, localRunners: localRunners),
                repositorySlug: localRunners.first?.repositorySlug,
                pid: nil,
                filePath: nil
            )
        }

        return macRunnerStatus(macRunners, for: project)
    }

    func repositoryRunners(for project: CIProject) async -> LoadResponse<[GitHubActionsRunner]> {
        if let pause = await GitHubRateLimitGate.shared.activePause() {
            return LoadResponse(error: pause.reason)
        }
        let command = "gh api --cache 30s \(quoted("repos/\(project.repositorySlug)/actions/runners"))"
        let result = await ShellClient.run(command, timeout: 15, config: config)
        await GitHubRateLimitGate.shared.note(result: result, config: config)
        guard result.exitCode == 0, let data = result.output.data(using: .utf8) else {
            return LoadResponse(error: trimmedError(result.output, fallback: "Could not read repo runners."))
        }

        guard let runnerList = try? JSONDecoder().decode(GitHubRunnerList.self, from: data) else {
            return LoadResponse(error: "Could not parse repo runners.")
        }

        return LoadResponse(value: runnerList.runners)
    }

    func unknownRepositoryRunnerStatus(
        detail: String,
        localRunners: [LocalRunnerInfo]
    ) -> ProjectLocalRunnerStatus {
        ProjectLocalRunnerStatus(
            state: .warning,
            summary: "Runner status unknown",
            detail: detail,
            repositorySlug: localRunners.first?.repositorySlug,
            pid: nil,
            filePath: nil
        )
    }

    func macRunnerStatus(_ macRunners: [GitHubActionsRunner], for project: CIProject) -> ProjectLocalRunnerStatus {
        let onlineRunner = macRunners.first { $0.status.lowercased() == "online" && !$0.busy }
        let busyRunner = macRunners.first { $0.status.lowercased() == "online" && $0.busy }
        let selectedRunner = onlineRunner ?? busyRunner ?? macRunners[0]
        let state: ServiceState =
            if onlineRunner != nil {
                .online
            } else if busyRunner != nil {
                .warning
            } else {
                .offline
            }
        let summary =
            if onlineRunner != nil {
                "Repo runner online"
            } else if busyRunner != nil {
                "Repo runner busy"
            } else {
                "Repo runner offline"
            }

        return ProjectLocalRunnerStatus(
            state: state,
            summary: summary,
            detail: selectedRunner.name,
            repositorySlug: project.repositorySlug,
            pid: nil,
            filePath: nil
        )
    }

    func localRunnerStatus(_ runner: LocalRunnerInfo, for project: CIProject) async -> ProjectLocalRunnerStatus {
        guard let serviceLabel = serviceLabel(for: runner.config) else {
            return ProjectLocalRunnerStatus(
                state: .warning,
                summary: "Runner configured",
                detail: "Service not installed for \(runner.config.title).",
                repositorySlug: runner.repositorySlug ?? project.repositorySlug,
                pid: nil,
                filePath: runner.config.runnerConfigurationPath
            )
        }

        let launch = await launchctlPrint(serviceLabel: serviceLabel)

        guard let output = launch?.output, launch?.exitCode == 0 else {
            let errorOutput = launch?.output ?? "Could not verify current user ID."
            let fallbackError = "launchctl could not read \(runner.config.title)."
            return ProjectLocalRunnerStatus(
                state: .offline,
                summary: "Service unavailable",
                detail: trimmedError(errorOutput, fallback: fallbackError),
                repositorySlug: runner.repositorySlug ?? project.repositorySlug,
                pid: nil,
                filePath: runner.config.runnerConfigurationPath
            )
        }

        let launchState = firstMatch(in: output, pattern: #"state = ([a-zA-Z]+)"#) ?? "unknown"
        let pid = intMatch(in: output, pattern: #"pid = ([0-9]+)"#)
        let uptime = await processUptime(pid: pid)
        let state: ServiceState = launchState == "running" ? .online : .offline
        let remoteRunner = await remoteRunner(matching: runner)
        let missingLabels = missingLabels(for: runner, remoteRunner: remoteRunner)
        let hasRequiredLabels = missingLabels.isEmpty
        let labelSummary = hasRequiredLabels ? launchState.capitalized : "Label mismatch"
        let detail =
            hasRequiredLabels
            ? "\(runner.config.title) · PID \(pid.map(String.init) ?? "-") · \(uptime)"
            : "\(runner.config.title) is missing required labels: \(missingLabels.joined(separator: ", "))"

        return ProjectLocalRunnerStatus(
            state: hasRequiredLabels ? state : .warning,
            summary: labelSummary,
            detail: detail,
            repositorySlug: runner.repositorySlug ?? project.repositorySlug,
            pid: pid,
            filePath: runner.config.runnerConfigurationPath
        )
    }

    func launchctlPrint(serviceLabel: String) async -> ShellResult? {
        return await ShellClient.run("launchctl print gui/\(geteuid())/\(quoted(serviceLabel))", timeout: 5, config: config)
    }

    func readLocalRunner(_ runnerConfig: ActionsRunnerConfig) -> LocalRunnerInfo? {
        guard let runner = readRunnerConfiguration(path: runnerConfig.runnerConfigurationPath) else {
            return nil
        }

        return LocalRunnerInfo(
            config: runnerConfig,
            runner: runner,
            repositorySlug: gitHubSlug(from: runner.gitHubUrl),
            owner: gitHubOwner(from: runner.gitHubUrl)
        )
    }

    func localRunner(_ runner: LocalRunnerInfo, appliesTo project: CIProject) -> Bool {
        switch runner.config.scope {
        case .organization(let organization):
            return project.repositoryOwner.caseInsensitiveCompare(organization) == .orderedSame
                && runner.owner?.caseInsensitiveCompare(organization) == .orderedSame
        case .personalAccount(let account):
            return project.repositoryOwner.caseInsensitiveCompare(account) == .orderedSame
                && runner.repositorySlug?.lowercased() == project.normalizedSlug
        case .repository(let slug):
            return project.normalizedSlug == slug.lowercased()
                && runner.repositorySlug?.lowercased() == project.normalizedSlug
        }
    }

    func serviceLabel(for runnerConfig: ActionsRunnerConfig) -> String? {
        if let serviceLabel = runnerConfig.serviceLabel {
            return serviceLabel
        }

        let servicePath = runnerConfig.root + "/.service"
        guard
            let contents = try? String(contentsOfFile: servicePath, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !contents.isEmpty
        else {
            return nil
        }

        return URL(fileURLWithPath: contents)
            .deletingPathExtension()
            .lastPathComponent
    }

    func missingRunnerDetail(for project: CIProject, localRunners: [LocalRunnerInfo]) -> String {
        if let orgRunner = config.actionsRunners.first(where: { runnerConfig in
            if case .organization(let organization) = runnerConfig.scope {
                return project.repositoryOwner.caseInsensitiveCompare(organization) == .orderedSame
            }
            return false
        }) {
            return "Use MacBook Runner for \(orgRunner.scope.description) with labels: \(orgRunner.requiredLabels.joined(separator: ", "))."
        }

        if config.actionsRunners.contains(where: { runnerConfig in
            if case .personalAccount(let account) = runnerConfig.scope {
                return project.repositoryOwner.caseInsensitiveCompare(account) == .orderedSame
            }
            return false
        }) {
            return
                "Attach \(project.repositorySlug) to MacBook Runner. Private sub-runner labels: \(LocalBrokerConstants.runnerLabels.joined(separator: ", "))."
        }

        if let localRunner = localRunners.first {
            return
                "Standalone runner is registered to \(localRunner.repositorySlug ?? localRunner.owner ?? localRunner.config.scope.description)."
        }

        return "No configured MacBook runner scope matches \(project.repositorySlug)."
    }

    func remoteRunner(matching runner: LocalRunnerInfo) async -> GitHubActionsRunner? {
        if await GitHubRateLimitGate.shared.isPaused() { return nil }
        let command: String?
        switch runner.config.scope {
        case .organization(let organization):
            command = "gh api --cache 30s \(quoted("orgs/\(organization)/actions/runners"))"
        case .personalAccount, .repository:
            guard let repositorySlug = runner.repositorySlug else { return nil }
            command = "gh api --cache 30s \(quoted("repos/\(repositorySlug)/actions/runners"))"
        }
        guard let command else { return nil }
        let result = await ShellClient.run(command, timeout: 15, config: config)
        await GitHubRateLimitGate.shared.note(result: result, config: config)
        guard result.exitCode == 0,
              let data = result.output.data(using: .utf8),
              let runnerList = try? JSONDecoder().decode(GitHubRunnerList.self, from: data)
        else { return nil }

        return runnerList.runners.first {
            $0.name.caseInsensitiveCompare(runner.runner.agentName ?? "") == .orderedSame
        }
    }

    func missingLabels(for runner: LocalRunnerInfo, remoteRunner: GitHubActionsRunner?) -> [String] {
        guard let remoteRunner else {
            return runner.config.requiredLabels
        }
        let availableLabels = Set(remoteRunner.labels.map { $0.name.lowercased() })
        return runner.config.requiredLabels.filter { !availableLabels.contains($0.lowercased()) }
    }
}
