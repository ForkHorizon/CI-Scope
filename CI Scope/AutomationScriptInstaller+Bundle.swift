import Foundation

extension AutomationScriptInstaller {
    static let bundleBranchName = "ci-scope/install-gates"

    /// Installs several gates in a single branch and pull request, instead of one
    /// PR per gate. Each script is rendered with its default variable values.
    func installBundle(
        scripts: [AutomationScript],
        project: CIProject,
        mode: AutomationScriptInstallMode
    ) async throws -> AutomationScriptInstallResult {
        _ = try await run("NO_COLOR=1 gh auth status -h github.com", step: "Check GitHub CLI authentication")
        try await validateBrokerAccessIfNeeded(mode: mode, project: project)
        for script in scripts {
            try validateRunnerLabelsSatisfiable(mode: mode, script: script, project: project)
        }
        try await attachBrokerIfNeeded(mode: mode, project: project)

        let defaultBranch = try await defaultBranch(for: project)
        let tempRoot = try temporaryRoot()
        let repoURL = try tempRoot.safelyAppendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        try await clone(project: project, defaultBranch: defaultBranch, into: repoURL)
        let branch = Self.bundleBranchName
        let branchExists = await remoteBranchExists(branch, cwd: repoURL)
        try await checkoutBranch(branch, exists: branchExists, cwd: repoURL)

        let touched = try await stageAll(scripts, project: project, defaultBranch: defaultBranch, mode: mode, repoURL: repoURL)

        if try await hasStagedChanges(files: touched, cwd: repoURL) {
            try await commitAndPushBundle(branch: branch, cwd: repoURL)
        }
        guard try await branchDiffersFromDefault(defaultBranch: defaultBranch, cwd: repoURL) else {
            return bundleResult(count: scripts.count, pullRequestURL: nil, alreadyInstalled: true)
        }
        let pullRequestURL = try await bundlePullRequestURL(
            project: project, scripts: scripts, defaultBranch: defaultBranch, branch: branch, tempRoot: tempRoot
        )
        return bundleResult(count: scripts.count, pullRequestURL: pullRequestURL, alreadyInstalled: false)
    }

    private func stageAll(
        _ scripts: [AutomationScript],
        project: CIProject,
        defaultBranch: String,
        mode: AutomationScriptInstallMode,
        repoURL: URL
    ) async throws -> [AutomationScriptFile] {
        var touched: [AutomationScriptFile] = []
        for script in scripts {
            let renderer = AutomationScriptRenderer(
                script: script,
                project: project,
                variableValues: defaultVariableValues(for: script),
                defaultBranch: defaultBranch,
                runnerLabelsOverride: runnerLabels(for: mode, script: script, project: project)
            )
            try renderer.validate()
            let files = try renderer.renderedFiles()
            try write(files, to: repoURL)
            try await stage(files, cwd: repoURL)
            touched += files
        }
        return touched
    }

    private func defaultVariableValues(for script: AutomationScript) -> [String: String] {
        Dictionary(uniqueKeysWithValues: script.variables.map { ($0.id, $0.defaultValue) })
    }

    private func commitAndPushBundle(branch: String, cwd: URL) async throws {
        _ = try await run(
            """
            git -c user.name='CI Scope' -c user.email='ci-scope@users.noreply.github.com' commit -m 'Add CI Scope quality gates'
            git push --set-upstream origin \(quoted(branch))
            """,
            cwd: cwd,
            timeout: 180,
            step: "Commit and push quality gates"
        )
    }

    private func bundlePullRequestURL(
        project: CIProject,
        scripts: [AutomationScript],
        defaultBranch: String,
        branch: String,
        tempRoot: URL
    ) async throws -> URL? {
        if let existingURL = try await existingPullRequestURL(project: project, branch: branch) {
            return existingURL
        }
        let draft = PullRequestDraft(
            base: defaultBranch,
            branch: branch,
            title: "Add CI Scope quality gates",
            body: bundlePullRequestBody(for: scripts)
        )
        return try await createPullRequest(project: project, draft: draft, tempRoot: tempRoot)
    }

    private func bundlePullRequestBody(for scripts: [AutomationScript]) -> String {
        let rows = scripts.map { "- **\($0.title)** — \($0.summary)" }.joined(separator: "\n")
        return """
            Adds the recommended CI Scope quality gates for this repository:

            \(rows)

            Each gate calls a reusable workflow in ForkHorizon/ci-gates, so gate logic updates roll out centrally.
            """
    }

    private func bundleResult(count: Int, pullRequestURL: URL?, alreadyInstalled: Bool) -> AutomationScriptInstallResult {
        if alreadyInstalled {
            return AutomationScriptInstallResult(
                title: "Gates already installed",
                detail: "The recommended gates already match the default branch.",
                pullRequestURL: nil
            )
        }
        return AutomationScriptInstallResult(
            title: "\(count) gate\(count == 1 ? "" : "s") PR ready",
            detail: "Open and merge the PR to enable the recommended gates.",
            pullRequestURL: pullRequestURL
        )
    }
}
