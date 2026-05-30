import Foundation
import Combine

struct ReadabilityGateInstallSnapshot: Equatable {
    var state: ServiceState
    var title: String
    var detail: String
    var isInstalling: Bool
    var pullRequestURL: URL?

    static let idle = ReadabilityGateInstallSnapshot(
        state: .unknown,
        title: "AI readability gate",
        detail: "Not installed from this session.",
        isInstalling: false,
        pullRequestURL: nil
    )

    static func installing() -> ReadabilityGateInstallSnapshot {
        ReadabilityGateInstallSnapshot(
            state: .warning,
            title: "Installing AI readability gate",
            detail: "Creating branch, writing files, and preparing a pull request.",
            isInstalling: true,
            pullRequestURL: nil
        )
    }

    static func succeeded(_ result: ReadabilityGateInstallResult) -> ReadabilityGateInstallSnapshot {
        ReadabilityGateInstallSnapshot(
            state: .online,
            title: result.title,
            detail: result.detail,
            isInstalling: false,
            pullRequestURL: result.pullRequestURL
        )
    }

    static func failed(_ message: String) -> ReadabilityGateInstallSnapshot {
        ReadabilityGateInstallSnapshot(
            state: .offline,
            title: "AI readability gate failed",
            detail: message,
            isInstalling: false,
            pullRequestURL: nil
        )
    }
}

struct ReadabilityGateInstallResult {
    let title: String
    let detail: String
    let pullRequestURL: URL?
}

@MainActor
final class ReadabilityGateInstallViewModel: ObservableObject {
    @Published private var snapshots: [CIProject.ID: ReadabilityGateInstallSnapshot] = [:]

    private let installer: ReadabilityGateInstaller

    init() {
        self.installer = ReadabilityGateInstaller(config: DashboardConfig())
    }

    init(config: DashboardConfig) {
        self.installer = ReadabilityGateInstaller(config: config)
    }

    func snapshot(for project: CIProject) -> ReadabilityGateInstallSnapshot {
        snapshots[project.id] ?? .idle
    }

    func install(in project: CIProject, onSuccess: @escaping () -> Void = {}) {
        guard !snapshots.values.contains(where: \.isInstalling) else { return }

        snapshots[project.id] = .installing()

        Task {
            do {
                let result = try await installer.install(in: project)
                snapshots[project.id] = .succeeded(result)
                onSuccess()
            } catch {
                snapshots[project.id] = .failed(error.localizedDescription)
            }
        }
    }
}

struct ReadabilityGateInstaller {
    private let config: DashboardConfig
    private let branchName = "ci-scope/install-ai-readability-gate"
    private let fileManager = FileManager.default

    init(config: DashboardConfig) {
        self.config = config
    }

    func install(in project: CIProject) async throws -> ReadabilityGateInstallResult {
        let templates = try ReadabilityGateTemplates.load()
        _ = try await run("NO_COLOR=1 gh auth status -h github.com", step: "Check GitHub CLI authentication")

        let defaultBranch = try await defaultBranch(for: project)
        let tempRoot = fileManager.temporaryDirectory
            .appendingPathComponent("ci-scope-readability-\(UUID().uuidString)", isDirectory: true)
        let repoURL = tempRoot.appendingPathComponent("repo", isDirectory: true)

        try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempRoot) }

        try await clone(project: project, defaultBranch: defaultBranch, into: repoURL)
        let branchExists = await remoteBranchExists(branchName, cwd: repoURL)
        try await checkoutInstallBranch(branchExists: branchExists, cwd: repoURL)
        try write(templates, to: repoURL)
        try await stageTemplates(cwd: repoURL)

        if try await hasStagedChanges(cwd: repoURL) {
            try await commitAndPush(cwd: repoURL)
        }

        guard try await branchDiffersFromDefault(defaultBranch: defaultBranch, cwd: repoURL) else {
            return ReadabilityGateInstallResult(
                title: "AI readability gate already installed",
                detail: "The readability gate files already match \(defaultBranch).",
                pullRequestURL: nil
            )
        }

        let pullRequestURL: URL?
        if let existingURL = try await existingPullRequestURL(for: project) {
            pullRequestURL = existingURL
        } else {
            pullRequestURL = try await createPullRequest(
                for: project,
                defaultBranch: defaultBranch,
                tempRoot: tempRoot
            )
        }

        return ReadabilityGateInstallResult(
            title: "AI readability gate PR ready",
            detail: "Open and merge the PR. CI needs a ci-scope self-hosted macOS ARM64 runner for this repo.",
            pullRequestURL: pullRequestURL
        )
    }

    private func defaultBranch(for project: CIProject) async throws -> String {
        let output = try await run(
            "gh repo view \(quoted(project.repositorySlug)) --json defaultBranchRef --jq '.defaultBranchRef.name'",
            step: "Read default branch"
        )
        let branch = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !branch.isEmpty else {
            throw ReadabilityGateInstallerError.invalidDefaultBranch(project.repositorySlug)
        }
        return branch
    }

    private func clone(project: CIProject, defaultBranch: String, into repoURL: URL) async throws {
        _ = try await run(
            """
            gh repo clone \(quoted(project.repositorySlug)) \(quoted(repoURL.path)) -- --depth 1 --branch \(quoted(defaultBranch))
            """,
            timeout: 180,
            step: "Clone repository"
        )
    }

    private func remoteBranchExists(_ branch: String, cwd: URL) async -> Bool {
        let result = await shell(
            "git ls-remote --exit-code --heads origin \(quoted(branch))",
            cwd: cwd,
            timeout: 30
        )
        return result.exitCode == 0
    }

    private func checkoutInstallBranch(branchExists: Bool, cwd: URL) async throws {
        if branchExists {
            _ = try await run(
                "git fetch origin \(quoted("\(branchName):refs/remotes/origin/\(branchName)"))",
                cwd: cwd,
                timeout: 60,
                step: "Fetch install branch"
            )
            _ = try await run(
                "git checkout -B \(quoted(branchName)) \(quoted("refs/remotes/origin/\(branchName)"))",
                cwd: cwd,
                step: "Checkout install branch"
            )
        } else {
            _ = try await run(
                "git checkout -B \(quoted(branchName))",
                cwd: cwd,
                step: "Create install branch"
            )
        }
    }

    private func write(_ templates: [ReadabilityGateTemplate], to repoURL: URL) throws {
        for template in templates {
            let destinationURL = repoURL.appendingPathComponent(template.destinationPath)
            try fileManager.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try template.contents.write(to: destinationURL, atomically: true, encoding: .utf8)
        }
    }

    private func stageTemplates(cwd: URL) async throws {
        _ = try await run(
            """
            chmod +x scripts/ai-readability-check.py
            git add .ai-readability.json .github/workflows/ai-readability.yml scripts/ai-readability-check.py
            git update-index --chmod=+x scripts/ai-readability-check.py
            """,
            cwd: cwd,
            step: "Stage readability gate files"
        )
    }

    private func hasStagedChanges(cwd: URL) async throws -> Bool {
        try await diffHasChanges(
            "git diff --cached --quiet -- .ai-readability.json .github/workflows/ai-readability.yml scripts/ai-readability-check.py",
            cwd: cwd,
            step: "Check staged changes"
        )
    }

    private func commitAndPush(cwd: URL) async throws {
        _ = try await run(
            """
            git -c user.name='CI Scope' -c user.email='ci-scope@users.noreply.github.com' commit -m 'Add AI readability gate'
            git push --set-upstream origin \(quoted(branchName))
            """,
            cwd: cwd,
            timeout: 180,
            step: "Commit and push readability gate"
        )
    }

    private func branchDiffersFromDefault(defaultBranch: String, cwd: URL) async throws -> Bool {
        try await diffHasChanges(
            "git diff --quiet \(quoted("refs/remotes/origin/\(defaultBranch)")) HEAD --",
            cwd: cwd,
            step: "Compare install branch with default branch"
        )
    }

    private func existingPullRequestURL(for project: CIProject) async throws -> URL? {
        let result = await shell(
            "gh pr view \(quoted(branchName)) --repo \(quoted(project.repositorySlug)) --json url --jq '.url'",
            timeout: 30
        )
        guard result.exitCode == 0 else { return nil }
        return URL(string: result.output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func createPullRequest(
        for project: CIProject,
        defaultBranch: String,
        tempRoot: URL
    ) async throws -> URL? {
        let bodyURL = tempRoot.appendingPathComponent("pull-request-body.md")
        try pullRequestBody.write(to: bodyURL, atomically: true, encoding: .utf8)

        let output = try await run(
            """
            gh pr create \
              --repo \(quoted(project.repositorySlug)) \
              --base \(quoted(defaultBranch)) \
              --head \(quoted(branchName)) \
              --title 'Add AI readability gate' \
              --body-file \(quoted(bodyURL.path))
            """,
            timeout: 60,
            step: "Create readability gate pull request"
        )
        return URL(string: output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func diffHasChanges(_ command: String, cwd: URL, step: String) async throws -> Bool {
        let result = await shell(command, cwd: cwd)
        if result.exitCode == 0 { return false }
        if result.exitCode == 1 { return true }
        throw ReadabilityGateInstallerError.commandFailed(step: step, output: result.output)
    }

    private func run(
        _ command: String,
        cwd: URL? = nil,
        timeout: TimeInterval = 30,
        step: String
    ) async throws -> String {
        let result = await shell(command, cwd: cwd, timeout: timeout)
        guard result.exitCode == 0 else {
            throw ReadabilityGateInstallerError.commandFailed(step: step, output: result.output)
        }
        return result.output
    }

    private func shell(_ command: String, cwd: URL? = nil, timeout: TimeInterval = 30) async -> ShellResult {
        await ShellClient.run(command, cwd: cwd?.path, timeout: timeout, config: config)
    }

    private var pullRequestBody: String {
        """
        Adds the portable AI Readability Gate managed by CI Scope.

        This PR adds:
        - `.github/workflows/ai-readability.yml`
        - `.ai-readability.json`
        - `scripts/ai-readability-check.py`

        The workflow checks changed files on pull requests and merge queue runs, and scans the full repository on manual or scheduled runs.
        """
    }
}

private struct ReadabilityGateTemplate {
    let destinationPath: String
    let contents: String
}

private enum ReadabilityGateTemplates {
    static func load() throws -> [ReadabilityGateTemplate] {
        let root = try sourceRepositoryRoot()
        return try [
            template(".ai-readability.json", root: root),
            template(".github/workflows/ai-readability.yml", root: root),
            template("scripts/ai-readability-check.py", root: root)
        ]
    }

    private static func template(_ path: String, root: URL) throws -> ReadabilityGateTemplate {
        let url = root.appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ReadabilityGateInstallerError.missingTemplate(path)
        }
        return ReadabilityGateTemplate(
            destinationPath: path,
            contents: try String(contentsOf: url, encoding: .utf8)
        )
    }

    private static func sourceRepositoryRoot() throws -> URL {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        if hasTemplates(in: sourceRoot) {
            return sourceRoot
        }

        let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        if hasTemplates(in: currentDirectory) {
            return currentDirectory
        }

        throw ReadabilityGateInstallerError.missingTemplate(".ai-readability.json")
    }

    private static func hasTemplates(in root: URL) -> Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent(".ai-readability.json").path)
            && FileManager.default.fileExists(atPath: root.appendingPathComponent(".github/workflows/ai-readability.yml").path)
            && FileManager.default.fileExists(atPath: root.appendingPathComponent("scripts/ai-readability-check.py").path)
    }
}

private enum ReadabilityGateInstallerError: LocalizedError {
    case commandFailed(step: String, output: String)
    case invalidDefaultBranch(String)
    case missingTemplate(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let step, let output):
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(step) failed.\n\(trimmed.isEmpty ? "No command output." : trimmed)"
        case .invalidDefaultBranch(let slug):
            return "Could not read the default branch for \(slug)."
        case .missingTemplate(let path):
            return "Missing readability gate template: \(path)."
        }
    }
}

private func quoted(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}
