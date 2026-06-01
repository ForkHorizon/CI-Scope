import Foundation

enum LocalBrokerConstants {
    static let serviceLabel = "com.ci-scope.local-mac-broker"
    static let runnerLabels = ["self-hosted", "macOS", "ARM64", "ci-scope-broker"]
}

struct BrokerRegistry: Codable, Equatable {
    var version = 1
    var repos: [BrokerManagedRepo] = []

    static let empty = BrokerRegistry()
}

struct BrokerManagedRepo: Identifiable, Codable, Equatable {
    var slug: String
    var attachedAt: String
    var enabled: Bool
    var labels: [String]
    var lastError: String?

    var id: String { slug.lowercased() }
}

struct BrokerState: Codable, Equatable {
    var version: Int
    var updatedAt: String
    var servicePID: Int?
    var active: BrokerJob?
    var queue: [BrokerJob]
    var repos: [BrokerRepoStatus]
    var lastError: String?
    var retries: [String: Int]?

    static let empty = BrokerState(
        version: 1,
        updatedAt: "",
        servicePID: nil,
        active: nil,
        queue: [],
        repos: [],
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

    var id: String { slug.lowercased() }
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
            labels: labels
        )
    }
}
