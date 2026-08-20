import Foundation

private final class ProjectCIResponseCache {
    static let shared = ProjectCIResponseCache()

    private let lock = NSLock()
    private var auth: (storedAt: Date, value: GitHubAuthSnapshot)?
    private var workflows: [String: (storedAt: Date, value: LoadResponse<[GitHubWorkflow]>)] = [:]
    private var runs: [String: (storedAt: Date, value: LoadResponse<[GitHubRun]>)] = [:]

    func cachedAuth(maxAge: TimeInterval) -> GitHubAuthSnapshot? {
        locked {
            guard let auth, Date().timeIntervalSince(auth.storedAt) <= maxAge else { return nil }
            return auth.value
        }
    }

    func storeAuth(_ value: GitHubAuthSnapshot) {
        locked {
            auth = (Date(), value)
        }
    }

    func cachedWorkflows(slug: String, maxAge: TimeInterval) -> LoadResponse<[GitHubWorkflow]>? {
        locked {
            guard let cached = workflows[slug.lowercased()],
                Date().timeIntervalSince(cached.storedAt) <= maxAge
            else { return nil }
            return cached.value
        }
    }

    func storeWorkflows(_ value: LoadResponse<[GitHubWorkflow]>, slug: String) {
        locked {
            workflows[slug.lowercased()] = (Date(), value)
        }
    }

    func invalidateWorkflows(slug: String) {
        locked {
            workflows[slug.lowercased()] = nil
        }
    }

    func cachedRuns(slug: String, maxAge: TimeInterval) -> LoadResponse<[GitHubRun]>? {
        locked {
            guard let cached = runs[slug.lowercased()],
                Date().timeIntervalSince(cached.storedAt) <= maxAge
            else { return nil }
            return cached.value
        }
    }

    func storeRuns(_ value: LoadResponse<[GitHubRun]>, slug: String) {
        locked {
            runs[slug.lowercased()] = (Date(), value)
        }
    }

    private func locked<Value>(_ body: () -> Value) -> Value {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

extension ProjectCIService {
    /// Drops the cached `gh workflow list` result for a repo so the next load
    /// sees a just-installed/removed workflow instead of a stale pre-change
    /// snapshot (cache TTL is 900s, longer than anyone will wait after an install).
    static func invalidateWorkflowsCache(forRepositorySlug slug: String) {
        ProjectCIResponseCache.shared.invalidateWorkflows(slug: slug)
    }

    func loadAuthStatus() async -> GitHubAuthSnapshot {
        if let cached = ProjectCIResponseCache.shared.cachedAuth(maxAge: 900) {
            return cached
        }
        let command = "NO_COLOR=1 gh auth status -h github.com"
        let result = await ShellClient.run(command, timeout: 10, config: config)
        let detail = sanitizeAuthOutput(trimmedError(result.output, fallback: "GitHub CLI auth status is unavailable."))
        let account = accountName(from: detail)

        if result.exitCode == 0 {
            let snapshot = GitHubAuthSnapshot(
                state: .online,
                account: account ?? "-",
                summary: account.map { "Authenticated as \($0)" } ?? "Authenticated",
                detail: nil
            )
            ProjectCIResponseCache.shared.storeAuth(snapshot)
            return snapshot
        }

        let snapshot = GitHubAuthSnapshot(
            state: .offline,
            account: account ?? "-",
            summary: "Authentication failed",
            detail: detail
        )
        ProjectCIResponseCache.shared.storeAuth(snapshot)
        return snapshot
    }

    func loadWorkflows(for project: CIProject, forceRefresh: Bool = false) async -> LoadResponse<[GitHubWorkflow]> {
        if !forceRefresh, let cached = ProjectCIResponseCache.shared.cachedWorkflows(slug: project.repositorySlug, maxAge: 900) {
            return cached
        }
        if await GitHubRateLimitGate.shared.isPaused() {
            let response = await loadWorkflowFilesViaGit(for: project, apiError: "GitHub rate limit reached.")
            ProjectCIResponseCache.shared.storeWorkflows(response, slug: project.repositorySlug)
            return response
        }
        let command = """
            gh workflow list --repo \(quoted(project.repositorySlug)) --all --limit 100 --json id,name,path,state
            """
        let result = await ShellClient.run(command, timeout: 15, config: config)
        await GitHubRateLimitGate.shared.note(result: result, config: config)
        if result.exitCode != 0 || result.output.data(using: .utf8) == nil {
            let response = await loadWorkflowFilesViaGit(
                for: project,
                apiError: trimmedError(result.output, fallback: "Failed to load workflows.")
            )
            ProjectCIResponseCache.shared.storeWorkflows(response, slug: project.repositorySlug)
            return response
        }

        if result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let response = LoadResponse(value: [GitHubWorkflow]())
            ProjectCIResponseCache.shared.storeWorkflows(response, slug: project.repositorySlug)
            return response
        }

        guard let data = result.output.data(using: .utf8) else {
            let response = LoadResponse<[GitHubWorkflow]>(error: "Failed to read workflow response.")
            ProjectCIResponseCache.shared.storeWorkflows(response, slug: project.repositorySlug)
            return response
        }

        do {
            let response = LoadResponse(value: try JSONDecoder().decode([GitHubWorkflow].self, from: data))
            ProjectCIResponseCache.shared.storeWorkflows(response, slug: project.repositorySlug)
            return response
        } catch {
            let response = LoadResponse<[GitHubWorkflow]>(error: error.localizedDescription)
            ProjectCIResponseCache.shared.storeWorkflows(response, slug: project.repositorySlug)
            return response
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

    func workflowSource(for project: CIProject, path: String) async -> String? {
        let command = "set -o pipefail; gh api \(quoted("repos/\(project.repositorySlug)/contents/\(path)")) --jq .content | base64 -D"
        let result = await ShellClient.run(command, timeout: 15, config: config)
        return result.exitCode == 0 ? result.output : nil
    }

    func loadRuns(for project: CIProject, forceRefresh: Bool = false) async -> LoadResponse<[GitHubRun]> {
        if !forceRefresh, let cached = ProjectCIResponseCache.shared.cachedRuns(slug: project.repositorySlug, maxAge: 30) {
            let hasActiveRuns = cached.value?.contains { $0.status == "in_progress" || $0.status == "queued" } ?? false
            if !hasActiveRuns {
                return cached
            }
        }
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
            let response = LoadResponse<[GitHubRun]>(error: trimmedError(result.output, fallback: "Failed to load workflow runs."))
            ProjectCIResponseCache.shared.storeRuns(response, slug: project.repositorySlug)
            return response
        }

        do {
            let response = LoadResponse(value: try JSONDecoder().decode([GitHubRun].self, from: data))
            ProjectCIResponseCache.shared.storeRuns(response, slug: project.repositorySlug)
            return response
        } catch {
            let response = LoadResponse<[GitHubRun]>(error: error.localizedDescription)
            ProjectCIResponseCache.shared.storeRuns(response, slug: project.repositorySlug)
            return response
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
