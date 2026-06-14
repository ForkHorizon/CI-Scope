import Foundation

struct LocalBrokerService {
    let config: DashboardConfig
    let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(config: DashboardConfig = DashboardConfig()) {
        self.config = config
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func attach(project: CIProject) async throws {
        try ensureDirectories()
        var registry = loadRegistry()
        if registry.profiles.contains(where: { profile in
            guard profile.enabled, profile.kind == .organization, let organization = profile.organization else {
                return false
            }
            return project.repositoryOwner.caseInsensitiveCompare(organization) == .orderedSame
        }) {
            try writeRegistry(registry)
            _ = try? await installOrUpdateLaunchAgent()
            return
        }

        let slug = project.repositorySlug
        let repo = BrokerManagedRepo(
            slug: slug,
            attachedAt: ISO8601DateFormatter().string(from: Date()),
            enabled: true,
            labels: LocalBrokerConstants.runnerLabels,
            lastError: nil
        )

        if let index = registry.repos.firstIndex(where: { $0.id == repo.id }) {
            registry.repos[index] = repo
        } else {
            registry.repos.append(repo)
        }
        try writeRegistry(registry)
        _ = try? await installOrUpdateLaunchAgent()
    }

    func isManaged(project: CIProject) -> Bool {
        let registry = loadRegistry()
        if registry.repos.contains(where: {
            $0.enabled && $0.slug.caseInsensitiveCompare(project.repositorySlug) == .orderedSame
        }) {
            return true
        }

        return registry.profiles.contains { profile in
            guard profile.enabled, profile.kind == .organization, let organization = profile.organization else {
                return false
            }
            return project.repositoryOwner.caseInsensitiveCompare(organization) == .orderedSame
        }
    }

    func loadRegistry() -> BrokerRegistry {
        guard
            let data = try? Data(contentsOf: registryURL),
            let registry = try? decoder.decode(BrokerRegistry.self, from: data)
        else {
            return .empty
        }
        return registry
    }

    func loadState() -> BrokerState {
        guard
            let data = try? Data(contentsOf: stateURL),
            let state = try? decoder.decode(BrokerState.self, from: data)
        else {
            return .empty
        }
        return state
    }

    func writeRegistry(_ registry: BrokerRegistry) throws {
        try ensureDirectories()
        let data = try encoder.encode(registry)
        try data.write(to: registryURL, options: .atomic)
    }

    func ensureDirectories() throws {
        try fileManager.createDirectory(at: brokerDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
    }

    var brokerDirectory: URL {
        try! applicationSupportDirectory.safelyAppendingPathComponent("Broker", isDirectory: true)
    }

    var registryURL: URL {
        try! brokerDirectory.safelyAppendingPathComponent("managed-repos.json")
    }

    var stateURL: URL {
        try! brokerDirectory.safelyAppendingPathComponent("broker-state.json")
    }

    var workflowRunsURL: URL {
        try! brokerDirectory.safelyAppendingPathComponent("workflow-runs.json")
    }

    var logsDirectory: URL {
        try! fileManager.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .safelyAppendingPathComponent("Logs/CI Scope/Broker", isDirectory: true)
    }

    private var applicationSupportDirectory: URL {
        try! fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .safelyAppendingPathComponent("CI Scope", isDirectory: true)
    }
}
