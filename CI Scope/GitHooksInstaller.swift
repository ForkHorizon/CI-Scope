// Installs the global ci-scope git hooks once per device without replacing another hooks path.
import Foundation

/// Installs the CI Scope git hooks once per device (one global core.hooksPath) using the pinned
/// ci-gates checkout. pre-commit runs the fast checks, pre-push the full set, only for registered repos.
struct GitHooksInstaller {
    var gatesRoot: URL
    var hooksDirectory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/ci-scope/hooks")
    /// When set, install only from a checkout at exactly this commit; `requireCleanCheckout` also refuses local edits.
    var expectedGatesSHA: String?
    var requireCleanCheckout = false
    var run: (String) async -> ShellResult = { await ShellClient.run($0, timeout: 30, config: DashboardConfig()) }

    enum State: Equatable {
        case installed
        case notInstalled
        case otherHooksPath(String)
    }

    func state() async -> State {
        let result = await run("git config --global --get core.hooksPath")
        let path = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if path.isEmpty { return .notInstalled }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardized
            == hooksDirectory.standardized ? .installed : .otherHooksPath(path)
    }

    /// Fails instead of replacing a different global hooks path someone already set.
    func install() async throws {
        if case .otherHooksPath(let path) = await state() {
            throw InstallError.otherHooksPath(path)
        }
        try await verifyCheckout()
        let script = gatesRoot.appendingPathComponent("scripts/install_hooks.py").path
        let result = await run("python3 \(quoted(script)) \(quoted(hooksDirectory.path))")
        guard result.exitCode == 0 else { throw InstallError.failed(result.output) }
    }

    /// The hooks run on every commit, so they must come from the reviewed gates commit and nothing edited on disk.
    private func verifyCheckout() async throws {
        let root = quoted(gatesRoot.path)
        if let expected = expectedGatesSHA {
            let head = await run("git -C \(root) rev-parse HEAD").output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard head == expected else {
                throw InstallError.untrustedCheckout("the checkout is at \(head.prefix(8)), not the pinned \(expected.prefix(8))")
            }
        }
        if requireCleanCheckout {
            let status = await run("git -C \(root) status --porcelain --untracked-files=all")
            guard status.exitCode == 0, status.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw InstallError.untrustedCheckout("the checkout has local changes")
            }
        }
    }

    enum InstallError: LocalizedError, Equatable {
        case otherHooksPath(String)
        case failed(String)
        case untrustedCheckout(String)

        var errorDescription: String? {
            switch self {
            case .otherHooksPath(let path):
                "git already uses \(path) for hooks. CI Scope will not replace it; remove that setting first."
            case .failed(let output): "Installing the git hooks failed: \(output)"
            case .untrustedCheckout(let reason): "CI Scope will not install hooks from the gates folder: \(reason)."
            }
        }
    }
}
