import Foundation

/// The branch/base/title/body of a pull request the installer is about to open.
struct PullRequestDraft {
    let base: String
    let branch: String
    let title: String
    let body: String
}

extension AutomationScriptInstaller {
    func pullRequestURL(
        project: CIProject,
        renderer: AutomationScriptRenderer,
        tempRoot: URL
    ) async throws -> URL? {
        if let existingURL = try await existingPullRequestURL(
            project: project, branch: renderer.branchName)
        {
            return existingURL
        }
        let draft = PullRequestDraft(
            base: renderer.defaultBranch,
            branch: renderer.branchName,
            title: renderer.pullRequestTitle,
            body: renderer.pullRequestBody
        )
        return try await createPullRequest(project: project, draft: draft, tempRoot: tempRoot)
    }

    func removalPullRequestURL(
        project: CIProject,
        script: AutomationScript,
        defaultBranch: String,
        branchName: String,
        tempRoot: URL
    ) async throws -> URL? {
        if let existingURL = try await existingPullRequestURL(project: project, branch: branchName) {
            return existingURL
        }
        let draft = PullRequestDraft(
            base: defaultBranch,
            branch: branchName,
            title: "Remove \(script.title) automation",
            body: removalPullRequestBody(for: script)
        )
        return try await createPullRequest(project: project, draft: draft, tempRoot: tempRoot)
    }

    func existingPullRequestURL(project: CIProject, branch: String) async throws -> URL? {
        let result = await shell(
            """
            gh pr list \
              --repo \(quoted(project.repositorySlug)) \
              --head \(quoted(branch)) \
              --state open \
              --json url \
              --jq '.[0].url // empty'
            """,
            timeout: 30
        )
        guard result.exitCode == 0 else { return nil }
        let url = result.output.trimmed
        return url.isEmpty ? nil : URL(string: url)
    }

    func createPullRequest(
        project: CIProject,
        draft: PullRequestDraft,
        tempRoot: URL
    ) async throws -> URL? {
        let bodyURL = try tempRoot.safelyAppendingPathComponent("pull-request-body.md")
        try draft.body.write(to: bodyURL, atomically: true, encoding: .utf8)
        let output = try await run(
            """
            gh pr create \
              --repo \(quoted(project.repositorySlug)) \
              --base \(quoted(draft.base)) \
              --head \(quoted(draft.branch)) \
              --title \(quoted(draft.title)) \
              --body-file \(quoted(bodyURL.path))
            """,
            timeout: 60,
            step: "Create automation script pull request"
        )
        let pullRequestURL = URL(string: output.trimmed)
        await enableAutoMergeIfConfigured(project: project, pullRequestURL: pullRequestURL)
        return pullRequestURL
    }

    /// Best effort: turns on GitHub auto-merge when the user opted in. Never
    /// throws — a repo that doesn't allow auto-merge just leaves the PR open.
    private func enableAutoMergeIfConfigured(project: CIProject, pullRequestURL: URL?) async {
        guard
            UserDefaults.standard.bool(forKey: CIQueueSettingsStore.autoMergeDefaultsKey),
            let pullRequestURL
        else { return }
        _ = await shell(
            "gh pr merge --auto --squash --repo \(quoted(project.repositorySlug)) \(quoted(pullRequestURL.absoluteString))",
            timeout: 30
        )
    }

    func alreadyInstalledResult(_ script: AutomationScript, defaultBranch: String)
        -> AutomationScriptInstallResult
    {
        AutomationScriptInstallResult(
            title: "\(script.title) already installed",
            detail: "The rendered script files already match \(defaultBranch).",
            pullRequestURL: nil
        )
    }

    func readyResult(_ script: AutomationScript, pullRequestURL: URL?)
        -> AutomationScriptInstallResult
    {
        AutomationScriptInstallResult(
            title: "\(script.title) PR ready",
            detail: "Open and merge the PR. The workflow uses this script's configured runner labels.",
            pullRequestURL: pullRequestURL
        )
    }

    func alreadyRemovedResult(_ script: AutomationScript, defaultBranch: String)
        -> AutomationScriptInstallResult
    {
        AutomationScriptInstallResult(
            title: "\(script.title) already removed",
            detail: "No installed script files were found on \(defaultBranch).",
            pullRequestURL: nil
        )
    }

    func removalReadyResult(_ script: AutomationScript, pullRequestURL: URL?)
        -> AutomationScriptInstallResult
    {
        AutomationScriptInstallResult(
            title: "\(script.title) removal PR ready",
            detail: "Open and merge the PR to remove this script from the project.",
            pullRequestURL: pullRequestURL
        )
    }

    func removalPullRequestBody(for script: AutomationScript) -> String {
        """
        Removes the \(script.title) automation managed by CI Scope.

        This PR removes the files currently configured in the script library item.
        """
    }
}
