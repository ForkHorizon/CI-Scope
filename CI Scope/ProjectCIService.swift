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
        let runnerPath = config.runnerRoot + "/.runner"
        guard let runner = readRunnerConfiguration(path: runnerPath) else {
            return ProjectLocalRunnerStatus(
                state: .unknown,
                summary: "No runner config",
                detail: runnerPath,
                repositorySlug: nil,
                pid: nil,
                filePath: runnerPath
            )
        }

        let runnerSlug = gitHubSlug(from: runner.gitHubUrl)
        guard runnerSlug?.lowercased() == project.normalizedSlug else {
            return ProjectLocalRunnerStatus(
                state: .unknown,
                summary: runnerSlug.map { "Registered to \($0)" } ?? "Runner repo unknown",
                detail: runner.agentName ?? "Local runner",
                repositorySlug: runnerSlug,
                pid: nil,
                filePath: runnerPath
            )
        }

        let uid = await ShellClient.run("id -u", timeout: 3, config: config)
            .output
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let launch = await ShellClient.run("launchctl print gui/\(uid)/\(config.runnerServiceLabel)", timeout: 5, config: config)

        guard launch.exitCode == 0 else {
            return ProjectLocalRunnerStatus(
                state: .offline,
                summary: "Service unavailable",
                detail: trimmedError(launch.output, fallback: "launchctl could not read runner service."),
                repositorySlug: runnerSlug,
                pid: nil,
                filePath: runnerPath
            )
        }

        let launchState = firstMatch(in: launch.output, pattern: #"state = ([a-zA-Z]+)"#) ?? "unknown"
        let pid = intMatch(in: launch.output, pattern: #"pid = ([0-9]+)"#)
        let uptime = await processUptime(pid: pid)
        let state: ServiceState = launchState == "running" ? .online : .offline
        let detail = "PID \(pid.map(String.init) ?? "-") · \(uptime)"

        return ProjectLocalRunnerStatus(
            state: state,
            summary: launchState.capitalized,
            detail: detail,
            repositorySlug: runnerSlug,
            pid: pid,
            filePath: runnerPath
        )
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

private struct LoadResponse<Value> {
    var value: Value?
    var error: String?
}

private extension Substring {
    var nilIfEmpty: Substring? {
        isEmpty ? nil : self
    }
}
