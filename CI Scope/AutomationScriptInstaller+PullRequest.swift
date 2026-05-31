import Foundation

extension AutomationScriptInstaller {
    func pullRequestURL(
        project: CIProject,
        renderer: AutomationScriptRenderer,
        tempRoot: URL
    ) async throws -> URL? {
        if let existingURL = try await existingPullRequestURL(project: project, branch: renderer.branchName) {
            return existingURL
        }
        return try await createPullRequest(project: project, renderer: renderer, tempRoot: tempRoot)
    }

    func existingPullRequestURL(project: CIProject, branch: String) async throws -> URL? {
        let result = await shell(
            "gh pr view \(quoted(branch)) --repo \(quoted(project.repositorySlug)) --json url --jq '.url'",
            timeout: 30
        )
        guard result.exitCode == 0 else { return nil }
        return URL(string: result.output.trimmed)
    }

    func createPullRequest(
        project: CIProject,
        renderer: AutomationScriptRenderer,
        tempRoot: URL
    ) async throws -> URL? {
        let bodyURL = tempRoot.appendingPathComponent("pull-request-body.md")
        try renderer.pullRequestBody.write(to: bodyURL, atomically: true, encoding: .utf8)
        let output = try await run(
            """
            gh pr create \
              --repo \(quoted(project.repositorySlug)) \
              --base \(quoted(renderer.defaultBranch)) \
              --head \(quoted(renderer.branchName)) \
              --title \(quoted(renderer.pullRequestTitle)) \
              --body-file \(quoted(bodyURL.path))
            """,
            timeout: 60,
            step: "Create automation script pull request"
        )
        return URL(string: output.trimmed)
    }

    func alreadyInstalledResult(_ script: AutomationScript, defaultBranch: String) -> AutomationScriptInstallResult {
        AutomationScriptInstallResult(
            title: "\(script.title) already installed",
            detail: "The rendered script files already match \(defaultBranch).",
            pullRequestURL: nil
        )
    }

    func readyResult(_ script: AutomationScript, pullRequestURL: URL?) -> AutomationScriptInstallResult {
        AutomationScriptInstallResult(
            title: "\(script.title) PR ready",
            detail: "Open and merge the PR. The workflow uses this script's configured runner labels.",
            pullRequestURL: pullRequestURL
        )
    }
}
