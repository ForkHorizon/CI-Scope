import Foundation

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
