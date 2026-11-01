import Combine
import Foundation

/// Pending `ci-scope/policy/` PRs across all projects, and the Touch ID–gated
/// approve actions. One Touch ID prompt covers a whole "Approve all" batch.
@MainActor
final class PolicyAdminViewModel: ObservableObject {
    @Published private(set) var changes: [PolicyPullRequest] = []
    @Published private(set) var statuses: [PolicyPullRequest.ID: PolicyChangeStatus] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var isApproving = false
    @Published var message: String?

    var service = PolicyAdminService()

    var pendingCount: Int {
        changes.filter { statuses[$0.id]?.needsApproval ?? true }.count
    }

    func load(projects: [CIProject]) async {
        isLoading = true
        defer { isLoading = false }
        let readToken = try? await PolicyAuthorizer.readToken()
        var found: [PolicyPullRequest] = []
        var unreachable = 0
        for project in projects {
            do {
                found += try await service.github.policyPullRequests(repository: project.repositorySlug)
            } catch {
                unreachable += 1  // keep the last known rows instead of silently dropping them
                found += changes.filter { $0.repository == project.repositorySlug }
            }
        }
        var loaded: [PolicyPullRequest.ID: PolicyChangeStatus] = [:]
        for change in found {
            if case .working = statuses[change.id] {
                loaded[change.id] = statuses[change.id]
                continue
            }
            loaded[change.id] =
                if let readToken { await service.status(of: change, readToken: readToken) } else {
                    .failed("Couldn't read the policy token from the server.")
                }
        }
        changes = found.filter { loaded[$0.id] != .active }
        statuses = loaded
        message = unreachable == 0 ? nil : "GitHub didn't answer for \(unreachable) repo(s); showing the last known state."
        if readToken == nil {
            message = PolicyAuthorizerError.serverUnreachable("CI_SCOPE_POLICY_READ_TOKEN").localizedDescription
        }
    }

    func approve(_ change: PolicyPullRequest) async {
        await approveBatch([change], reason: "approve the CI policy change \(change.repository)#\(change.number)")
    }

    func approveAll() async {
        let pending = changes.filter { statuses[$0.id]?.needsApproval ?? false }
        guard !pending.isEmpty else { return }
        await approveBatch(pending, reason: "approve \(pending.count) CI policy change(s)")
    }

    /// Used by the checks editor: the PR it just opened is approved in the same batch.
    func approveNew(_ change: PolicyPullRequest, credentials: (password: String, readToken: String)) async -> Bool {
        changes.append(change)
        statuses[change.id] = .awaitingMerge
        return await run(change, credentials: credentials)
    }

    private func approveBatch(_ batch: [PolicyPullRequest], reason: String) async {
        isApproving = true
        defer { isApproving = false }
        message = nil
        do {
            let password = try await PolicyAuthorizer.adminPassword(reason: reason)
            let credentials = (password: password, readToken: try await PolicyAuthorizer.readToken())
            for change in batch where !(await run(change, credentials: credentials)) {
                message = "Stopped at \(change.repository)#\(change.number). Fix it and press Retry; later changes weren't touched."
                return
            }
        } catch {
            message = error.localizedDescription
        }
    }

    private func run(_ change: PolicyPullRequest, credentials: (password: String, readToken: String)) async -> Bool {
        let id = change.id
        do {
            try await service.approve(change, credentials: credentials) { [weak self] step in
                self?.statuses[id] = .working(step)
            }
            statuses[id] = .active
            return true
        } catch {
            statuses[id] = .failed(error.localizedDescription)
            return false
        }
    }
}
