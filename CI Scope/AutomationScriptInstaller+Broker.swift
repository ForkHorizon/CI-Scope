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
            throw LocalBrokerError.invalidRepository("Could not read repository permission for Local Mac Broker.")
        }
        guard repo.viewerPermission == "ADMIN" else {
            throw LocalBrokerError.invalidRepository(
                "Local Mac Broker needs admin access to create JIT runners for \(project.repositorySlug).")
        }
    }

    func attachBrokerIfNeeded(mode: AutomationScriptInstallMode, project: CIProject) async throws {
        guard mode == .localBroker else { return }
        try await LocalBrokerService(config: config).attach(project: project)
    }
}

private struct BrokerRepositoryAccess: Decodable {
    let viewerPermission: String
}
