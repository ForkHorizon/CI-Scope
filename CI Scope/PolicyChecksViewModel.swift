import Combine
import Foundation

/// Per-project check toggles. A toggle only stages an edit; "Apply" is the one
/// Touch ID prompt that opens the policy PR, merges it and activates it.
@MainActor
final class PolicyChecksViewModel: ObservableObject {
    static let branches = ["main", "develop", "developer"]

    @Published var branch = "main"
    @Published private(set) var original: String?
    @Published private(set) var edited: String?
    @Published private(set) var loadError: String?
    @Published private(set) var isBusy = false
    @Published var message: String?
    private var blobSHA = ""

    let github = PolicyGitHub(config: DashboardConfig())

    var checkIDs: [String] {
        PolicyManifestEditor.checkIDs(in: edited ?? original ?? "")
    }

    /// Catalog types plus anything already in the manifest (e.g. a retired slop-review).
    var rows: [String] {
        let present = PolicyManifestEditor.checkIDs(in: original ?? "")
        let catalog = PolicyManifestEditor.templates.keys.sorted()
        return catalog + present.filter { !catalog.contains($0) }
    }

    var hasChanges: Bool { edited != nil && edited != original }

    var summary: String {
        let before = Set(PolicyManifestEditor.checkIDs(in: original ?? ""))
        let after = Set(checkIDs)
        let parts =
            after.subtracting(before).sorted().map { "enable \($0)" }
            + before.subtracting(after).sorted().map { "disable \($0)" }
        return parts.joined(separator: ", ")
    }

    func load(_ project: CIProject) async {
        original = nil
        edited = nil
        loadError = nil
        message = nil
        do {
            let file = try await github.file(repository: project.repositorySlug, ref: branch, path: ".ci-scope.json")
            original = String(data: file.data, encoding: .utf8)
            blobSHA = file.blobSHA
        } catch {
            loadError = "No .ci-scope.json on \(branch) (or it couldn't be read)."
        }
    }

    func toggle(_ id: String, on: Bool) {
        message = nil
        do {
            let current = edited ?? original ?? ""
            let next = try on ? PolicyManifestEditor.adding(id, to: current) : PolicyManifestEditor.removing(id, from: current)
            // Back to the original set: keep the original text (custom workdirs etc.), not a template.
            let unchanged = Set(PolicyManifestEditor.checkIDs(in: next)) == Set(PolicyManifestEditor.checkIDs(in: original ?? ""))
            edited = unchanged ? nil : next
        } catch {
            message = error.localizedDescription
        }
    }

    func discard() {
        edited = nil
        message = nil
    }

    func apply(to project: CIProject, admin: PolicyAdminViewModel) async {
        guard hasChanges, let edited else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let change = PolicyGitHub.ManifestChange(
                repository: project.repositorySlug, branch: branch, text: edited, blobSHA: blobSHA, summary: summary)
            let password = try await PolicyAuthorizer.adminPassword(
                reason: "\(summary) on \(project.repositorySlug) \(branch)")
            let credentials = (password: password, readToken: try await PolicyAuthorizer.readToken())
            let pullRequest = try await github.propose(change)
            let activated = await admin.approveNew(pullRequest, credentials: credentials)
            message = activated ? "Done: \(summary) is live on \(branch)." : "The PR was opened but not activated. See Pending."
            await load(project)
        } catch {
            message = error.localizedDescription
        }
    }
}
