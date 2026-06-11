import Foundation

enum ServiceState: String, Equatable {
    case online = "Online"
    case warning = "Warning"
    case offline = "Offline"
    case unknown = "Unknown"
}

struct GitHubRun: Identifiable, Decodable {
    let databaseId: Int
    let status: String
    let conclusion: String?
    let displayTitle: String
    let workflowName: String
    let headBranch: String
    let event: String
    let createdAt: String
    let updatedAt: String
    let url: String

    var id: Int { databaseId }

    var compactConclusion: String {
        conclusion ?? status
    }
}

struct GitHubWorkflow: Identifiable, Decodable {
    let id: String
    let name: String
    let path: String?
    let state: String

    init(id: String, name: String, path: String?, state: String) {
        self.id = id
        self.name = name
        self.path = path
        self.state = state
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let intID = try? container.decode(Int.self, forKey: .id) {
            id = String(intID)
        } else {
            id = try container.decode(String.self, forKey: .id)
        }
        name = try container.decode(String.self, forKey: .name)
        path = try container.decodeIfPresent(String.self, forKey: .path)
        state = try container.decode(String.self, forKey: .state)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case path
        case state
    }
}

struct ProjectCISnapshot {
    let projectID: CIProject.ID
    var state: ServiceState = .unknown
    var localRunner = ProjectLocalRunnerStatus()
    var workflows: [GitHubWorkflow] = []
    var runs: [GitHubRun] = []
    var error: String?
    var refreshedAt = Date()
}

struct ProjectLocalRunnerStatus {
    var state: ServiceState = .unknown
    var summary = "Checking"
    var detail = "-"
    var repositorySlug: String?
    var pid: Int?
    var filePath: String?
}
