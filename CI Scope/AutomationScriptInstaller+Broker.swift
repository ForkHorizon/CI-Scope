import Foundation

extension AutomationScriptInstaller {
    func validateBrokerAccessIfNeeded(mode: AutomationScriptInstallMode, project: CIProject) async throws {
        guard mode == .localBroker else { return }
        let output = try await run(
            "gh repo view \(quoted(project.repositorySlug)) --json viewerPermission",
            timeout: 30,
            step: "Check broker repository access"
        )
        guard let data = output.data(using: .utf8),
            let repo = try? JSONDecoder().decode(BrokerRepositoryAccess.self, from: data)
        else {
            throw LocalBrokerError.invalidRepository("Could not read repository permission for MacBook Runner.")
        }
        guard repo.viewerPermission == "ADMIN" else {
            throw LocalBrokerError.invalidRepository(
                "MacBook Runner needs admin access to create JIT runners for \(project.repositorySlug).")
        }
    }

    func attachBrokerIfNeeded(mode: AutomationScriptInstallMode, project: CIProject) async throws {
        guard mode == .localBroker else { return }
        try await LocalBrokerService(config: config).attach(project: project)
    }

    func runnerLabels(
        for mode: AutomationScriptInstallMode,
        script: AutomationScript,
        project: CIProject
    ) -> [String] {
        guard mode == .localBroker else {
            return mode.runnerLabels(for: script)
        }

        let registry = LocalBrokerService(config: config).loadRegistry()
        if let organizationProfile = registry.profiles.first(where: { profile in
            guard profile.enabled, profile.kind == .organization, let organization = profile.organization else {
                return false
            }
            return project.repositoryOwner.caseInsensitiveCompare(organization) == .orderedSame
        }) {
            return organizationProfile.labels
        }

        if let repo = registry.repos.first(where: {
            $0.enabled && $0.slug.caseInsensitiveCompare(project.repositorySlug) == .orderedSame
        }), !repo.labels.isEmpty {
            return repo.labels
        }

        return LocalBrokerConstants.runnerLabels
    }
}

private struct BrokerRepositoryAccess: Decodable {
    let viewerPermission: String
}
