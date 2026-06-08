import Foundation

enum LocalBrokerConstants {
    static let serviceLabel = "com.ci-scope.local-mac-broker"
    static let organizationProfileID = "forkhorizon-organization"
    static let privateProfileID = "daliys-private"
    static let organizationRunnerLabels = ["self-hosted", "macOS", "ARM64", "ci-scope"]
    static let runnerLabels = ["self-hosted", "macOS", "ARM64", "ci-scope-broker"]
    static let stateStaleAfterSeconds: TimeInterval = 75
}

struct BrokerRegistry: Codable, Equatable {
    var version = 1
    var repos: [BrokerManagedRepo] = []
    var profiles: [BrokerRunnerProfile] = BrokerRunnerProfile.defaultProfiles

    static let empty = BrokerRegistry()

    init(version: Int = 1, repos: [BrokerManagedRepo] = [], profiles: [BrokerRunnerProfile] = BrokerRunnerProfile.defaultProfiles) {
        self.version = version
        self.repos = repos
        self.profiles = profiles.isEmpty ? BrokerRunnerProfile.defaultProfiles : profiles
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        repos = try container.decodeIfPresent([BrokerManagedRepo].self, forKey: .repos) ?? []
        let decodedProfiles = try container.decodeIfPresent([BrokerRunnerProfile].self, forKey: .profiles) ?? []
        profiles = decodedProfiles.isEmpty ? BrokerRunnerProfile.defaultProfiles : decodedProfiles
    }
}

enum BrokerRunnerProfileKind: String, Codable, Equatable {
    case organization
    case privateRepositories
}

struct BrokerRunnerProfile: Identifiable, Codable, Equatable {
    var id: String
    var title: String
    var scope: String
    var kind: BrokerRunnerProfileKind
    var organization: String?
    var labels: [String]
    var enabled: Bool

    static let defaultProfiles = [
        BrokerRunnerProfile(
            id: LocalBrokerConstants.organizationProfileID,
            title: "ForkHorizon organization",
            scope: "ForkHorizon organization",
            kind: .organization,
            organization: "ForkHorizon",
            labels: LocalBrokerConstants.organizationRunnerLabels,
            enabled: true
        ),
        BrokerRunnerProfile(
            id: LocalBrokerConstants.privateProfileID,
            title: "Daliys private repositories",
            scope: "Daliys private repositories",
            kind: .privateRepositories,
            organization: nil,
            labels: LocalBrokerConstants.runnerLabels,
            enabled: true
        )
    ]
}

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
    var queue: [BrokerJob]
    var repos: [BrokerRepoStatus]
    var profiles: [BrokerRunnerProfile]?
    var lastError: String?
    var retries: [String: Int]?

    static let empty = BrokerState(
        version: 1,
        updatedAt: "",
        servicePID: nil,
        active: nil,
        queue: [],
        repos: [],
        profiles: nil,
        lastError: nil,
        retries: [:]
    )
}

struct BrokerRepoStatus: Identifiable, Codable, Equatable {
    var slug: String
    var state: String
    var queuedCount: Int
    var lastCheckedAt: String
    var lastError: String?
    var profileID: String?
    var profileTitle: String?
    var profileScope: String?
    var labels: [String]?

    var id: String { slug.lowercased() }

    private enum CodingKeys: String, CodingKey {
        case slug
        case state
        case queuedCount
        case lastCheckedAt
        case lastError
        case profileID = "profileId"
        case profileTitle
        case profileScope
        case labels
    }
}

struct BrokerJob: Identifiable, Codable, Equatable {
    var id: String
    var repositorySlug: String
    var workflowName: String
    var title: String
    var jobName: String
    var headBranch: String
    var status: String
    var url: String
    var createdAt: String
    var labels: [String]
    var runId: Int64?
    var jobId: Int64?
    var profileID: String?
    var profileTitle: String?
    var profileScope: String?

    var workItem: RunnerWorkItem {
        RunnerWorkItem(
            id: id,
            repositorySlug: repositorySlug,
            workflowName: workflowName,
            title: title,
            jobName: jobName,
            headBranch: headBranch,
            status: status,
            url: url,
            createdAt: createdAt,
            labels: labels,
            assemblerID: profileID,
            assemblerTitle: profileTitle,
            assemblerScope: profileScope
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case repositorySlug
        case workflowName
        case title
        case jobName
        case headBranch
        case status
        case url
        case createdAt
        case labels
        case runId
        case jobId
        case profileID = "profileId"
        case profileTitle
        case profileScope
    }
}
