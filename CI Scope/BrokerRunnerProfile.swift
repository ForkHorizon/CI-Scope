import Foundation

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
            id: LocalBrokerConstants.organizationBrokerProfileID,
            title: "ForkHorizon broker workflows",
            scope: "ForkHorizon organization",
            kind: .organization,
            organization: "ForkHorizon",
            labels: LocalBrokerConstants.organizationBrokerRunnerLabels,
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
        ),
    ]
}
