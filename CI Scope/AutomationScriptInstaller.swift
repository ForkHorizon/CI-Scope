import Foundation

struct AutomationScriptInstaller {
    let config: DashboardConfig
    private let fileManager = FileManager.default

    init(config: DashboardConfig) {
        self.config = config
    }

    func install(
        script: AutomationScript,
        project: CIProject,
        variableValues: [String: String]
    ) async throws -> AutomationScriptInstallResult {
        _ = try await run("NO_COLOR=1 gh auth status -h github.com", step: "Check GitHub CLI authentication")
        let defaultBranch = try await defaultBranch(for: project)
        let renderer = AutomationScriptRenderer(
            script: script,
            project: project,
            variableValues: variableValues,
            defaultBranch: defaultBranch
        )
        try renderer.validate()

        let tempRoot = temporaryRoot()
        let repoURL = tempRoot.appendingPathComponent("repo", isDirectory: true)
        try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempRoot) }

        try await clone(project: project, defaultBranch: defaultBranch, into: repoURL)
        let branchExists = await remoteBranchExists(renderer.branchName, cwd: repoURL)
        try await checkoutBranch(renderer.branchName, exists: branchExists, cwd: repoURL)
        let files = try renderer.renderedFiles()
        try write(files, to: repoURL)
        try await stage(files, cwd: repoURL)

        if try await hasStagedChanges(files: files, cwd: repoURL) {
            try await commitAndPush(renderer: renderer, cwd: repoURL)
        }
        guard try await branchDiffersFromDefault(defaultBranch: defaultBranch, cwd: repoURL) else {
            return alreadyInstalledResult(script, defaultBranch: defaultBranch)
        }
        let pullRequestURL = try await pullRequestURL(
            project: project,
            renderer: renderer,
            tempRoot: tempRoot
        )
        return readyResult(script, pullRequestURL: pullRequestURL)
    }

    private func defaultBranch(for project: CIProject) async throws -> String {
        let output = try await run(
            "gh repo view \(quoted(project.repositorySlug)) --json defaultBranchRef --jq '.defaultBranchRef.name'",
            step: "Read default branch"
        )
        let branch = output.trimmed
        guard !branch.isEmpty else {
            throw AutomationScriptError.invalidDefaultBranch(project.repositorySlug)
        }
        return branch
    }

    private func clone(project: CIProject, defaultBranch: String, into repoURL: URL) async throws {
        _ = try await run(
            "gh repo clone \(quoted(project.repositorySlug)) \(quoted(repoURL.path)) -- --depth 1 --branch \(quoted(defaultBranch))",
            timeout: 180,
            step: "Clone repository"
        )
    }

    private func remoteBranchExists(_ branch: String, cwd: URL) async -> Bool {
        let result = await shell("git ls-remote --exit-code --heads origin \(quoted(branch))", cwd: cwd)
        return result.exitCode == 0
    }

    private func checkoutBranch(_ branch: String, exists: Bool, cwd: URL) async throws {
        if exists {
            try await checkoutExistingBranch(branch, cwd: cwd)
        } else {
            _ = try await run("git checkout -B \(quoted(branch))", cwd: cwd, step: "Create install branch")
        }
    }

    private func checkoutExistingBranch(_ branch: String, cwd: URL) async throws {
        _ = try await run(
            "git fetch origin \(quoted("\(branch):refs/remotes/origin/\(branch)"))",
            cwd: cwd,
            timeout: 60,
            step: "Fetch install branch"
        )
        _ = try await run(
            "git checkout -B \(quoted(branch)) \(quoted("refs/remotes/origin/\(branch)"))",
            cwd: cwd,
            step: "Checkout install branch"
        )
    }

    private func write(_ files: [AutomationScriptFile], to repoURL: URL) throws {
        for file in files {
            let destinationURL = repoURL.appendingPathComponent(file.destinationPath)
            try fileManager.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try file.contents.write(to: destinationURL, atomically: true, encoding: .utf8)
        }
    }

    private func stage(_ files: [AutomationScriptFile], cwd: URL) async throws {
        _ = try await run(stageCommand(for: files), cwd: cwd, step: "Stage automation files")
    }

    private func stageCommand(for files: [AutomationScriptFile]) -> String {
        let paths = files.map { quoted($0.destinationPath) }.joined(separator: " ")
        let executablePaths = files.filter(\.isExecutable).map { quoted($0.destinationPath) }
        let chmod = executablePaths.isEmpty ? "" : "chmod +x \(executablePaths.joined(separator: " "))\n"
        let update = executablePaths.isEmpty ? "" : "git update-index --chmod=+x \(executablePaths.joined(separator: " "))\n"
        return "\(chmod)git add -- \(paths)\n\(update)"
    }

    private func hasStagedChanges(files: [AutomationScriptFile], cwd: URL) async throws -> Bool {
        try await diffHasChanges("git diff --cached --quiet -- \(gitPaths(files))", cwd: cwd, step: "Check staged changes")
    }

    private func commitAndPush(renderer: AutomationScriptRenderer, cwd: URL) async throws {
        _ = try await run(
            """
            git -c user.name='CI Scope' -c user.email='ci-scope@users.noreply.github.com' commit -m \(quoted(renderer.commitMessage))
            git push --set-upstream origin \(quoted(renderer.branchName))
            """,
            cwd: cwd,
            timeout: 180,
            step: "Commit and push automation script"
        )
    }

    private func branchDiffersFromDefault(defaultBranch: String, cwd: URL) async throws -> Bool {
        try await diffHasChanges(
            "git diff --quiet \(quoted("refs/remotes/origin/\(defaultBranch)")) HEAD --",
            cwd: cwd,
            step: "Compare install branch with default branch"
        )
    }
}
