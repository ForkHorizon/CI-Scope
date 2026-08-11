import Foundation

enum LocalBrokerConstants {
    static let serviceLabel = "com.ci-scope.local-mac-broker"
    static let organizationProfileID = "forkhorizon-organization"
    static let organizationBrokerProfileID = "forkhorizon-organization-broker"
    static let privateProfileID = "daliys-private"
    static let organizationRunnerLabels = ["self-hosted", "macOS", "ARM64", "ci-scope"]
    static let organizationBrokerRunnerLabels = ["self-hosted", "macOS", "ARM64", "ci-scope-broker"]
    static let runnerLabels = ["self-hosted", "macOS", "ARM64", "ci-scope-broker"]
    static let stateStaleAfterSeconds: TimeInterval = 75
    static let webhookPort = 8765
    static let webhookPath = "/github/workflow-job"
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
