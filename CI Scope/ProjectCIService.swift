import Foundation

struct ProjectCIService {
    let config: DashboardConfig

    func loadSnapshot(for project: CIProject) async -> ProjectCISnapshot {
        async let authResult = loadAuthStatus()
        async let workflowsResult = loadWorkflows(for: project)
        async let runsResult = loadRuns(for: project)
        async let localRunnerResult = loadLocalRunner(for: project)

        let authResponse = await authResult
        let workflowResponse = await workflowsResult
        let runResponse = await runsResult
        let localRunnerResponse = await localRunnerResult

        var snapshot = ProjectCISnapshot(projectID: project.id)
        snapshot.localRunner = localRunnerResponse
        snapshot.workflows = workflowResponse.value ?? []
        snapshot.runs = runResponse.value ?? []
        snapshot.refreshedAt = Date()

        var errors = [workflowResponse.error, runResponse.error].compactMap { $0 }
        if !errors.isEmpty {
            if authResponse.state == .offline, let detail = authResponse.detail {
                errors.insert("GitHub CLI auth:\n\(detail)", at: 0)
            }
            snapshot.state = snapshot.workflows.isEmpty && snapshot.runs.isEmpty ? .offline : .warning
            snapshot.error = errors.joined(separator: "\n\n")
            return snapshot
        }

        snapshot.state = state(workflows: snapshot.workflows, runs: snapshot.runs)
        return snapshot
    }

    private func loadLocalRunner(for project: CIProject) async -> ProjectLocalRunnerStatus {
        let localRunners = config.actionsRunners.compactMap(readLocalRunner)
        if let runner = localRunners.first(where: { localRunner($0, appliesTo: project) }) {
            return await localRunnerStatus(runner, for: project)
        }

        return await repositoryRunnerStatus(
            for: project,
            localRunners: localRunners
        )
    }

    private func repositoryRunnerStatus(
        for project: CIProject,
        localRunners: [LocalRunnerInfo]
    ) async -> ProjectLocalRunnerStatus {
        let command = "gh api \(quoted("repos/\(project.repositorySlug)/actions/runners"))"
        let result = await ShellClient.run(command, timeout: 15, config: config)
        guard result.exitCode == 0, let data = result.output.data(using: .utf8) else {
            return ProjectLocalRunnerStatus(
                state: .warning,
                summary: "Runner status unknown",
                detail: trimmedError(result.output, fallback: "Could not read repo runners."),
                repositorySlug: localRunners.first?.repositorySlug,
                pid: nil,
                filePath: nil
            )
        }

        guard let runnerList = try? JSONDecoder().decode(GitHubRunnerList.self, from: data) else {
            return ProjectLocalRunnerStatus(
                state: .warning,
                summary: "Runner status unknown",
                detail: "Could not parse repo runners.",
                repositorySlug: localRunners.first?.repositorySlug,
                pid: nil,
                filePath: nil
            )
        }

        let macRunners = runnerList.runners.filter { $0.hasLabels(config.actionsRunnerRequiredLabels) }
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

        let onlineRunner = macRunners.first { $0.status.lowercased() == "online" && !$0.busy }
        let busyRunner = macRunners.first { $0.status.lowercased() == "online" && $0.busy }
        let selectedRunner = onlineRunner ?? busyRunner ?? macRunners[0]
        let state: ServiceState = if onlineRunner != nil {
            .online
        } else if busyRunner != nil {
            .warning
        } else {
            .offline
        }
        let summary = if onlineRunner != nil {
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

    private func localRunnerStatus(_ runner: LocalRunnerInfo, for project: CIProject) async -> ProjectLocalRunnerStatus {
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

        let uid = await ShellClient.run("id -u", timeout: 3, config: config)
            .output
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let launch = await ShellClient.run("launchctl print gui/\(uid)/\(serviceLabel)", timeout: 5, config: config)

        guard launch.exitCode == 0 else {
            return ProjectLocalRunnerStatus(
                state: .offline,
                summary: "Service unavailable",
                detail: trimmedError(launch.output, fallback: "launchctl could not read \(runner.config.title)."),
                repositorySlug: runner.repositorySlug ?? project.repositorySlug,
                pid: nil,
                filePath: runner.config.runnerConfigurationPath
            )
        }

        let launchState = firstMatch(in: launch.output, pattern: #"state = ([a-zA-Z]+)"#) ?? "unknown"
        let pid = intMatch(in: launch.output, pattern: #"pid = ([0-9]+)"#)
        let uptime = await processUptime(pid: pid)
        let state: ServiceState = launchState == "running" ? .online : .offline
        let remoteRunner = await remoteRunner(matching: runner)
        let missingLabels = missingLabels(for: runner, remoteRunner: remoteRunner)
        let hasRequiredLabels = missingLabels.isEmpty
        let labelSummary = hasRequiredLabels ? launchState.capitalized : "Label mismatch"
        let detail = hasRequiredLabels
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

    private func readLocalRunner(_ runnerConfig: ActionsRunnerConfig) -> LocalRunnerInfo? {
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

    private func localRunner(_ runner: LocalRunnerInfo, appliesTo project: CIProject) -> Bool {
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

    private func serviceLabel(for runnerConfig: ActionsRunnerConfig) -> String? {
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

    private func missingRunnerDetail(for project: CIProject, localRunners: [LocalRunnerInfo]) -> String {
        if let orgRunner = config.actionsRunners.first(where: { runnerConfig in
            if case .organization(let organization) = runnerConfig.scope {
                return project.repositoryOwner.caseInsensitiveCompare(organization) == .orderedSame
            }
            return false
        }) {
            return "Install \(orgRunner.title) with labels: \(orgRunner.requiredLabels.joined(separator: ", "))."
        }

        if let personalRunner = config.actionsRunners.first(where: { runnerConfig in
            if case .personalAccount(let account) = runnerConfig.scope {
                return project.repositoryOwner.caseInsensitiveCompare(account) == .orderedSame
            }
            return false
        }) {
            return "Personal repos need a repo-level runner. Reconfigure \(personalRunner.title) to \(project.repositorySlug)."
        }

        if let localRunner = localRunners.first {
            return "Local runner is registered to \(localRunner.repositorySlug ?? localRunner.owner ?? localRunner.config.scope.description)."
        }

        return "No configured local runner scope matches \(project.repositorySlug)."
    }

    private func remoteRunner(matching runner: LocalRunnerInfo) async -> GitHubActionsRunner? {
        let command: String?
        switch runner.config.scope {
        case .organization(let organization):
            command = "gh api \(quoted("orgs/\(organization)/actions/runners"))"
        case .personalAccount, .repository:
            guard let repositorySlug = runner.repositorySlug else { return nil }
            command = "gh api \(quoted("repos/\(repositorySlug)/actions/runners"))"
        }

        guard let command else { return nil }
        let result = await ShellClient.run(command, timeout: 15, config: config)
        guard result.exitCode == 0, let data = result.output.data(using: .utf8) else {
            return nil
        }

        guard let runnerList = try? JSONDecoder().decode(GitHubRunnerList.self, from: data) else {
            return nil
        }

        return runnerList.runners.first {
            $0.name.caseInsensitiveCompare(runner.runner.agentName ?? "") == .orderedSame
        }
    }

    private func missingLabels(for runner: LocalRunnerInfo, remoteRunner: GitHubActionsRunner?) -> [String] {
        guard let remoteRunner else {
            return runner.config.requiredLabels
        }
        let availableLabels = Set(remoteRunner.labels.map { $0.name.lowercased() })
        return runner.config.requiredLabels.filter { !availableLabels.contains($0.lowercased()) }
    }

    private func loadAuthStatus() async -> GitHubAuthSnapshot {
        let command = "NO_COLOR=1 gh auth status -h github.com"
        let result = await ShellClient.run(command, timeout: 10, config: config)
        let detail = sanitizeAuthOutput(trimmedError(result.output, fallback: "GitHub CLI auth status is unavailable."))
        let account = accountName(from: detail)

        if result.exitCode == 0 {
            return GitHubAuthSnapshot(
                state: .online,
                account: account ?? "-",
                summary: account.map { "Authenticated as \($0)" } ?? "Authenticated",
                detail: nil
            )
        }

        return GitHubAuthSnapshot(
            state: .offline,
            account: account ?? "-",
            summary: "Authentication failed",
            detail: detail
        )
    }

    private func loadWorkflows(for project: CIProject) async -> LoadResponse<[GitHubWorkflow]> {
        let command = """
        gh workflow list --repo \(quoted(project.repositorySlug)) --all --limit 100 --json id,name,path,state
        """
        let result = await ShellClient.run(command, timeout: 15, config: config)
        if result.exitCode != 0 || result.output.data(using: .utf8) == nil {
            return await loadWorkflowFilesViaGit(
                for: project,
                apiError: trimmedError(result.output, fallback: "Failed to load workflows.")
            )
        }

        if result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return LoadResponse(value: [])
        }

        guard let data = result.output.data(using: .utf8) else {
            return LoadResponse(error: "Failed to read workflow response.")
        }

        do {
            return LoadResponse(value: try JSONDecoder().decode([GitHubWorkflow].self, from: data))
        } catch {
            return LoadResponse(error: error.localizedDescription)
        }
    }

    private func loadWorkflowFilesViaGit(for project: CIProject, apiError: String) async -> LoadResponse<[GitHubWorkflow]> {
        let command = """
        tmp=$(mktemp -d)
        cleanup() { rm -rf "$tmp"; }
        trap cleanup EXIT
        if git clone --depth 1 --filter=blob:none --sparse \(quoted(cloneURL(for: project))) "$tmp/repo" >/dev/null 2>&1; then
          cd "$tmp/repo" || exit 1
          git sparse-checkout set .github/workflows >/dev/null 2>&1 || true
          find .github/workflows -maxdepth 1 -type f \\( -name '*.yml' -o -name '*.yaml' \\) -print 2>/dev/null | sort
        fi
        """
        let result = await ShellClient.run(command, timeout: 30, config: config)
        let paths = result.output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !paths.isEmpty else {
            return LoadResponse(error: apiError)
        }

        let workflows = paths.map { path in
            GitHubWorkflow(
                id: "git:\(project.normalizedSlug):\(path)",
                name: workflowName(from: path),
                path: path,
                state: "detected"
            )
        }
        return LoadResponse(value: workflows)
    }

    private func loadRuns(for project: CIProject) async -> LoadResponse<[GitHubRun]> {
        let command = """
        gh run list --repo \(quoted(project.repositorySlug)) --limit 20 --json databaseId,status,conclusion,displayTitle,workflowName,headBranch,event,createdAt,updatedAt,url
        """
        let result = await ShellClient.run(command, timeout: 15, config: config)
        guard result.exitCode == 0, let data = result.output.data(using: .utf8) else {
            return LoadResponse(error: trimmedError(result.output, fallback: "Failed to load workflow runs."))
        }

        do {
            return LoadResponse(value: try JSONDecoder().decode([GitHubRun].self, from: data))
        } catch {
            return LoadResponse(error: error.localizedDescription)
        }
    }

    private func state(workflows: [GitHubWorkflow], runs: [GitHubRun]) -> ServiceState {
        guard let latestRun = runs.first else {
            return workflows.isEmpty ? .unknown : .online
        }

        if latestRun.status != "completed" {
            return .warning
        }

        return latestRun.conclusion == "success" ? .online : .offline
    }

    private func trimmedError(_ output: String, fallback: String) -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func cloneURL(for project: CIProject) -> String {
        if project.remoteURL.hasPrefix("git@") || project.remoteURL.hasPrefix("https://") {
            return project.remoteURL
        }
        return "git@github.com:\(project.repositorySlug).git"
    }

    private func workflowName(from path: String) -> String {
        let filename = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        return filename
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    private func sanitizeAuthOutput(_ output: String) -> String {
        output
            .components(separatedBy: .newlines)
            .map { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("- Token:") {
                    return line.replacingOccurrences(of: trimmed, with: "- Token: hidden")
                }
                return line
            }
            .joined(separator: "\n")
    }

    private func accountName(from output: String) -> String? {
        guard let range = output.range(of: "account ") else {
            return nil
        }

        let suffix = output[range.upperBound...]
        let terminators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "("))
        return suffix
            .prefix { character in
                String(character).rangeOfCharacter(from: terminators) == nil
            }
            .nilIfEmpty
            .map(String.init)
    }

    private func readRunnerConfiguration(path: String) -> RunnerConfiguration? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return nil
        }

        let jsonData: Data
        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            jsonData = data.dropFirst(3)
        } else {
            jsonData = data
        }

        return try? JSONDecoder().decode(RunnerConfiguration.self, from: jsonData)
    }

    private func gitHubSlug(from value: String?) -> String? {
        guard var value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        if value.hasPrefix("git@github.com:") {
            value = String(value.dropFirst("git@github.com:".count))
        } else if value.hasPrefix("https://github.com/") {
            value = String(value.dropFirst("https://github.com/".count))
        } else if value.hasPrefix("http://github.com/") {
            value = String(value.dropFirst("http://github.com/".count))
        }

        value = value
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        if value.hasSuffix(".git") {
            value = String(value.dropLast(4))
        }

        let parts = value.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count >= 2 else { return nil }
        return "\(parts[0])/\(parts[1])"
    }

    private func gitHubOwner(from value: String?) -> String? {
        guard var value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        if value.hasPrefix("git@github.com:") {
            value = String(value.dropFirst("git@github.com:".count))
        } else if value.hasPrefix("https://github.com/") {
            value = String(value.dropFirst("https://github.com/".count))
        } else if value.hasPrefix("http://github.com/") {
            value = String(value.dropFirst("http://github.com/".count))
        }

        value = value.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if value.hasSuffix(".git") {
            value = String(value.dropLast(4))
        }

        return value.split(separator: "/", omittingEmptySubsequences: true)
            .first
            .map(String.init)
    }

    private func processUptime(pid: Int?) async -> String {
        guard let pid else { return "-" }
        let result = await ShellClient.run("ps -p \(pid) -o etime= | xargs", timeout: 3, config: config)
        let uptime = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
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

    private func quoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

private struct GitHubAuthSnapshot {
    var state: ServiceState = .unknown
    var account = "-"
    var summary = "Not checked"
    var detail: String?
}

private struct RunnerConfiguration: Decodable {
    let agentName: String?
    let gitHubUrl: String?
}

private struct LocalRunnerInfo {
    let config: ActionsRunnerConfig
    let runner: RunnerConfiguration
    let repositorySlug: String?
    let owner: String?
}

private struct GitHubRunnerList: Decodable {
    let runners: [GitHubActionsRunner]
}

private struct GitHubActionsRunner: Decodable {
    let name: String
    let status: String
    let busy: Bool
    let labels: [GitHubRunnerLabel]

    func hasLabels(_ requiredLabels: [String]) -> Bool {
        let availableLabels = Set(labels.map { $0.name.lowercased() })
        return requiredLabels.allSatisfy { availableLabels.contains($0) }
    }
}

private struct GitHubRunnerLabel: Decodable {
    let name: String
}

private struct LoadResponse<Value> {
    var value: Value?
    var error: String?
}

private extension Substring {
    var nilIfEmpty: Substring? {
        isEmpty ? nil : self
    }
}
