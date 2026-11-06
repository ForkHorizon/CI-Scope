// State and actions for the per-project protection settings stored on the CI Scope server.
import AppKit
import Combine
import Foundation

@MainActor
final class ProjectProtectionViewModel: ObservableObject {
    @Published var config: ProjectConfig?
    @Published private(set) var isBusy = false
    /// The repository the current `config` and `message` belong to; differs from the selected project while a switch is loading.
    @Published private(set) var loadedRepository: String?
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

    /// Last known config per repository (nil = server said "not registered"), so switching projects shows data at once.
    private var cache: [String: ProjectConfig?] = [:]

    /// Shows the cached config immediately (if any), then revalidates against the server in the background.
    func load(repository: String) async {
        self.repository = repository
        if let hit = cache[repository] {
            config = hit
            message = nil
            loadedRepository = repository
        } else {
            isBusy = true
        }
        await fetch(repository, selected: true)
    }

    /// Warms the cache for every registered project, in parallel, so a click never waits on the network.
    func prefetch(_ repositories: [String]) async {
        await withTaskGroup(of: Void.self) { group in
            for repository in repositories { group.addTask { await self.fetch(repository, selected: false) } }
        }
    }

    private func fetch(_ repository: String, selected: Bool) async {
        let loaded: ProjectConfig?
        let note: String?
        do {
            loaded = try await client.read(repository: repository, readToken: try await readToken())
            note = nil
            cache[repository] = .some(loaded)
        } catch ProjectConfigError.server(let status, _) where status == 404 {
            loaded = nil
            note = "\(repository) is not registered with CI Scope yet."
            cache[repository] = .some(nil)
        } catch {
            // A failed refresh keeps what is already shown; only an empty screen gets the error.
            guard selected, self.repository == repository, loadedRepository != repository else {
                if selected, self.repository == repository { isBusy = false }
                return
            }
            config = nil
            message = error.localizedDescription
            loadedRepository = repository
            isBusy = false
            return
        }
        // A slower answer for a project the user already left must not overwrite the one now on screen.
        guard self.repository == repository else { return }
        if selected || !isBusy {
            config = loaded
            message = note
            loadedRepository = repository
        }
        if selected { isBusy = false }
    }

    /// Registers the project that was last loaded.
    func register() async { await register(repository: repository) }

    /// Registers the project with the safe defaults (code rules and agent guard on).
    func register(repository: String) async {
        self.repository = repository
        await guarded("register \(repository) with CI Scope") { admin in
            let registered = try await self.client.register(repository: repository, admin: admin)
            self.config = registered
            self.cache[repository] = .some(registered)
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
            let saved = try await client.update(edited, admin: admin)
            self.config = saved
            self.cache[self.repository] = .some(saved)
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
