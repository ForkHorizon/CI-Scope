// State and actions for the per-project protection settings stored on the CI Scope server.
import AppKit
import Combine
import Foundation

@MainActor
final class ProjectProtectionViewModel: ObservableObject {
    @Published var config: ProjectConfig?
    @Published private(set) var isBusy = false
    @Published private(set) var hooks: GitHooksInstaller.State = .notInstalled
    @Published var message: String?

    var client = ProjectConfigClient()
    var installer = GitHooksInstaller(
        gatesRoot: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ci-scope/gates"),
        requireCleanCheckout: true)
    var readToken: () async throws -> String = { try await ServerAuthorizer.configReadToken() }
    var adminLogin: (String) async throws -> (user: String, password: String) = { reason in
        try await ServerAuthorizer.adminLogin(reason: reason)
    }

    private var repository = ""

    /// Loads the project's config; a project the server does not know yet shows as unregistered.
    func load(repository: String) async {
        self.repository = repository
        isBusy = true
        defer { isBusy = false }
        do {
            config = try await client.read(repository: repository, readToken: try await readToken())
            message = nil
        } catch ProjectConfigError.server(let status, _) where status == 404 {
            config = nil
            message = "\(repository) is not registered with CI Scope yet."
        } catch {
            config = nil
            message = error.localizedDescription
        }
    }

    /// Registers the project that was last loaded.
    func register() async { await register(repository: repository) }

    /// Registers the project with the safe defaults (code rules and agent guard on).
    func register(repository: String) async {
        self.repository = repository
        await guarded("register \(repository) with CI Scope") { admin in
            self.config = try await self.client.register(repository: repository, admin: admin)
        }
    }

    /// Saves the edited config. Every save asks for Touch ID; the server decides whether it needs more.
    func save() async {
        guard let edited = config else { return }
        var client = self.client
        client.open = { page in
            Task { @MainActor in self.message = "Approve the change with Touch ID on the website that just opened." }
            NSWorkspace.shared.open(page)
        }
        await guarded("change the CI protection of \(repository)") { admin in
            self.config = try await client.update(edited, admin: admin)
        }
    }

    func refreshHooks() async {
        hooks = await installer.state()
    }

    func installHooks() async {
        do {
            try await installer.install()
            message = nil
        } catch {
            message = error.localizedDescription
        }
        await refreshHooks()
    }

    private func guarded(_ reason: String, _ action: @escaping ((user: String, password: String)) async throws -> Void) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await action(try await adminLogin(reason))
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }
}
