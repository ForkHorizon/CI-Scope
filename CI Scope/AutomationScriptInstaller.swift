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
        variableValues: [String: String],
        mode: AutomationScriptInstallMode
    ) async throws -> AutomationScriptInstallResult {
        _ = try await run("NO_COLOR=1 gh auth status -h github.com", step: "Check GitHub CLI authentication")
        try await validateBrokerAccessIfNeeded(mode: mode, project: project)
        let defaultBranch = try await defaultBranch(for: project)
        let renderer = AutomationScriptRenderer(
            script: script,
            project: project,
            variableValues: variableValues,
            defaultBranch: defaultBranch,
            runnerLabelsOverride: mode.runnerLabels(for: script)
        )
        try renderer.validate()

        let tempRoot = try temporaryRoot()
        let repoURL = try tempRoot.safelyAppendingPathComponent("repo", isDirectory: true)
        try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempRoot) }

        let touchedFiles = try await renderAndStageInstall(
            script: script,
            project: project,
            defaultBranch: defaultBranch,
            renderer: renderer,
            repoURL: repoURL
        )

        if try await hasStagedChanges(files: touchedFiles, cwd: repoURL) {
            try await commitAndPush(renderer: renderer, cwd: repoURL)
        }
        guard try await branchDiffersFromDefault(defaultBranch: defaultBranch, cwd: repoURL) else {
            try await attachBrokerIfNeeded(mode: mode, project: project)
            return alreadyInstalledResult(script, defaultBranch: defaultBranch)
        }
        let pullRequestURL = try await pullRequestURL(
            project: project,
            renderer: renderer,
            tempRoot: tempRoot
        )
        try await attachBrokerIfNeeded(mode: mode, project: project)
        return readyResult(script, pullRequestURL: pullRequestURL)
    }

    private func renderAndStageInstall(
        script: AutomationScript,
        project: CIProject,
        defaultBranch: String,
        renderer: AutomationScriptRenderer,
        repoURL: URL
    ) async throws -> [AutomationScriptFile] {
        try await clone(project: project, defaultBranch: defaultBranch, into: repoURL)
        let branchExists = await remoteBranchExists(renderer.branchName, cwd: repoURL)
        try await checkoutBranch(renderer.branchName, exists: branchExists, cwd: repoURL)
        let files = try renderer.renderedFiles()
        let obsoleteFiles = obsoleteInstalledFiles(for: script, currentFiles: files, cwd: repoURL)
        try await remove(obsoleteFiles, cwd: repoURL)
        try write(files, to: repoURL)
        try await stage(files, cwd: repoURL)
        return files + obsoleteFiles
    }

    func remove(
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
        try AutomationScriptValidator.validateForSave(script)

        let tempRoot = try temporaryRoot()
        let repoURL = try tempRoot.safelyAppendingPathComponent("repo", isDirectory: true)
        try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempRoot) }

        try await clone(project: project, defaultBranch: defaultBranch, into: repoURL)
        let branchName = "ci-scope/remove-\(script.id)"
        let branchExists = await remoteBranchExists(branchName, cwd: repoURL)
        try await checkoutBranch(branchName, exists: branchExists, cwd: repoURL)
        let files = try renderer.renderedFiles()
        let obsoleteFiles = obsoleteInstalledFiles(for: script, currentFiles: files, cwd: repoURL)
        let filesToRemove = files + obsoleteFiles
        try await remove(filesToRemove, cwd: repoURL)

        if try await hasStagedChanges(files: filesToRemove, cwd: repoURL) {
            try await commitAndPushRemoval(script: script, branchName: branchName, cwd: repoURL)
        }
        guard try await branchDiffersFromDefault(defaultBranch: defaultBranch, cwd: repoURL) else {
            return alreadyRemovedResult(script, defaultBranch: defaultBranch)
        }
        let pullRequestURL = try await removalPullRequestURL(
            project: project,
            script: script,
            defaultBranch: defaultBranch,
            branchName: branchName,
            tempRoot: tempRoot
        )
        return removalReadyResult(script, pullRequestURL: pullRequestURL)
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
            let destinationURL = try repoURL.safelyAppendingPathComponent(file.destinationPath)
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

    private func remove(_ files: [AutomationScriptFile], cwd: URL) async throws {
        guard !files.isEmpty else { return }
        _ = try await run(
            "git rm -f --ignore-unmatch -- \(gitPaths(files))",
            cwd: cwd,
            step: "Remove automation files"
        )
    }

    private func stageCommand(for files: [AutomationScriptFile]) -> String {
        let paths = files.map { quoted($0.destinationPath) }.joined(separator: " ")
        let executablePaths = files.filter(\.isExecutable).map { quoted($0.destinationPath) }
        let chmod = executablePaths.isEmpty ? "" : "chmod +x \(executablePaths.joined(separator: " "))\n"
        let stageExecutable = executablePaths.isEmpty ? "" : "git add -f --chmod=+x -- \(executablePaths.joined(separator: " "))\n"
        return "set -euo pipefail\n\(chmod)git add -f -- \(paths)\n\(stageExecutable)"
    }

    private func hasStagedChanges(files: [AutomationScriptFile], cwd: URL) async throws -> Bool {
        guard !files.isEmpty else { return false }
        return try await diffHasChanges("git diff --cached --quiet -- \(gitPaths(files))", cwd: cwd, step: "Check staged changes")
    }

    private func obsoleteInstalledFiles(
        for script: AutomationScript,
        currentFiles: [AutomationScriptFile],
        cwd: URL
    ) -> [AutomationScriptFile] {
        guard script.defaultSeedID == "ai-readability" || script.id == "ai-readability" else { return [] }

        let currentPaths = Set(currentFiles.map { normalizedPath($0.destinationPath) })
        return
            legacyReadabilityInstallPaths
            .filter { path in
                !currentPaths.contains(normalizedPath(path))
                    && fileManager.fileExists(atPath: (try? cwd.safelyAppendingPathComponent(path))?.path ?? "")
            }
            .map { path in
                AutomationScriptFile(
                    id: "obsolete-\(path)",
                    destinationPath: path,
                    isExecutable: false,
                    contents: ""
                )
            }
    }

    private var legacyReadabilityInstallPaths: [String] {
        [
            ".ai-readability.json",
            ".github/workflows/ai-readability.yml",
            "scripts/ai-readability-check.py",
        ]
    }

    private func normalizedPath(_ path: String) -> String {
        path
            .trimmed
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
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

    private func commitAndPushRemoval(script: AutomationScript, branchName: String, cwd: URL) async throws {
        _ = try await run(
            """
            git -c user.name='CI Scope' -c user.email='ci-scope@users.noreply.github.com' commit -m \(quoted("Remove \(script.title) automation"))
            git push --set-upstream origin \(quoted(branchName))
            """,
            cwd: cwd,
            timeout: 180,
            step: "Commit and push automation removal"
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
