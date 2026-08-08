import Foundation

struct BrokerManagedRepo: Identifiable, Codable, Equatable {
    var slug: String
    var attachedAt: String
    var enabled: Bool
    var labels: [String]
    var lastError: String?

    var id: String { slug.lowercased() }

    init(slug: String, attachedAt: String, enabled: Bool, labels: [String], lastError: String?) {
        self.slug = slug
        self.attachedAt = attachedAt
        self.enabled = enabled
        self.labels = labels.isEmpty ? LocalBrokerConstants.runnerLabels : labels
        self.lastError = lastError
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        slug = try container.decode(String.self, forKey: .slug)
        attachedAt = try container.decodeIfPresent(String.self, forKey: .attachedAt) ?? ""
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        labels = try container.decodeIfPresent([String].self, forKey: .labels) ?? LocalBrokerConstants.runnerLabels
        lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
    }
}

struct BrokerState: Codable, Equatable {
    var version: Int
    var updatedAt: String
    var servicePID: Int?
    var active: BrokerJob?
    var actives: [BrokerJob]?
    var queue: [BrokerJob]
    var repos: [BrokerRepoStatus]
    var profiles: [BrokerRunnerProfile]?
    var webhook: BrokerWebhookStatus?
    var lastError: String?
    var retries: [String: Int]?

    /// All jobs the broker is running right now. Prefers the parallel `actives`
    /// list and falls back to the legacy single `active` field for older state files.
    var activeJobs: [BrokerJob] {
        if let actives { return actives }
        if let active { return [active] }
        return []
    }

    static let empty = BrokerState(
        version: 1,
        updatedAt: "",
        servicePID: nil,
        active: nil,
        actives: nil,
        queue: [],
        repos: [],
        profiles: nil,
        webhook: nil,
        lastError: nil,
        retries: [:]
    )
}
