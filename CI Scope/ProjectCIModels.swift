import Foundation

struct GitHubAuthSnapshot {
    var state: ServiceState = .unknown
    var account = "-"
    var summary = "Not checked"
    var detail: String?
}

struct RunnerConfiguration: Decodable {
    let agentName: String?
    let gitHubUrl: String?
}

struct LocalRunnerInfo {
    let config: ActionsRunnerConfig
    let runner: RunnerConfiguration
    let repositorySlug: String?
    let owner: String?
}

struct GitHubRunnerList: Decodable {
    let runners: [GitHubActionsRunner]
}

struct GitHubActionsRunner: Decodable {
    let name: String
    let status: String
    let busy: Bool
    let labels: [GitHubRunnerLabel]

    func hasLabels(_ requiredLabels: [String]) -> Bool {
        let availableLabels = Set(labels.map { $0.name.lowercased() })
        return requiredLabels.allSatisfy { availableLabels.contains($0) }
    }
}

struct GitHubRunnerLabel: Decodable {
    let name: String
}

struct LoadResponse<Value> {
    var value: Value?
    var error: String?
}

extension Substring {
    var nilIfEmpty: Substring? {
        isEmpty ? nil : self
    }
}