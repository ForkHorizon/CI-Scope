// Installs the global ci-scope git hooks once per device without replacing another hooks path.
import Foundation

/// Installs the CI Scope git hooks once per device (one global core.hooksPath) using the pinned
/// ci-gates checkout. pre-commit runs the fast checks, pre-push the full set, only for registered repos.
struct GitHooksInstaller {
    var gatesRoot: URL
    var hooksDirectory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/ci-scope/hooks")
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
        let script = gatesRoot.appendingPathComponent("scripts/install_hooks.py").path
        let result = await run("python3 \(quoted(script)) \(quoted(hooksDirectory.path))")
        guard result.exitCode == 0 else { throw InstallError.failed(result.output) }
    }

    enum InstallError: LocalizedError, Equatable {
        case otherHooksPath(String)
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .otherHooksPath(let path):
                "git already uses \(path) for hooks. CI Scope will not replace it; remove that setting first."
            case .failed(let output): "Installing the git hooks failed: \(output)"
            }
        }
    }
}
