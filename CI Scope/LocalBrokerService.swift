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
        loadRegistry().repos.contains {
            $0.enabled && $0.slug.caseInsensitiveCompare(project.repositorySlug) == .orderedSame
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
        applicationSupportDirectory.appendingPathComponent("Broker", isDirectory: true)
    }

    var registryURL: URL {
        brokerDirectory.appendingPathComponent("managed-repos.json")
    }

    var stateURL: URL {
        brokerDirectory.appendingPathComponent("broker-state.json")
    }

    var logsDirectory: URL {
        fileManager.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/CI Scope/Broker", isDirectory: true)
    }

    private var applicationSupportDirectory: URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CI Scope", isDirectory: true)
    }
}
