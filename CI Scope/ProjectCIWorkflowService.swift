import Foundation

extension ProjectCIService {
    func loadAuthStatus() async -> GitHubAuthSnapshot {
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

    func loadWorkflows(for project: CIProject) async -> LoadResponse<[GitHubWorkflow]> {
        if await GitHubRateLimitGate.shared.isPaused() {
            return await loadWorkflowFilesViaGit(for: project, apiError: "GitHub rate limit reached.")
        }
        let command = """
        gh workflow list --repo \(quoted(project.repositorySlug)) --all --limit 100 --json id,name,path,state
        """
        let result = await ShellClient.run(command, timeout: 15, config: config)
        await GitHubRateLimitGate.shared.note(result: result, config: config)
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

    func loadWorkflowFilesViaGit(for project: CIProject, apiError: String) async -> LoadResponse<[GitHubWorkflow]> {
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

    func loadRuns(for project: CIProject) async -> LoadResponse<[GitHubRun]> {
        if let pause = await GitHubRateLimitGate.shared.activePause() {
            let when = pause.until.formatted(date: .omitted, time: .shortened)
            return LoadResponse(error: "\(pause.reason). Retrying after \(when).")
        }
        let command = """
        gh run list --repo \(quoted(project.repositorySlug)) --limit 20 --json databaseId,status,conclusion,displayTitle,workflowName,headBranch,event,createdAt,updatedAt,url
        """
        let result = await ShellClient.run(command, timeout: 15, config: config)
        await GitHubRateLimitGate.shared.note(result: result, config: config)
        guard result.exitCode == 0, let data = result.output.data(using: .utf8) else {
            return LoadResponse(error: trimmedError(result.output, fallback: "Failed to load workflow runs."))
        }

        do {
            return LoadResponse(value: try JSONDecoder().decode([GitHubRun].self, from: data))
        } catch {
            return LoadResponse(error: error.localizedDescription)
        }
    }

    func state(workflows: [GitHubWorkflow], runs: [GitHubRun]) -> ServiceState {
        guard let latestRun = runs.first else {
            return workflows.isEmpty ? .unknown : .online
        }

        if latestRun.status != "completed" {
            return .warning
        }

        return latestRun.conclusion == "success" ? .online : .offline
    }
}
