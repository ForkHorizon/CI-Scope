import Foundation

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
    var state: ServiceState = .unknown
    var localRunner = ProjectLocalRunnerStatus()
    var workflows: [GitHubWorkflow] = []
    var runs: [GitHubRun] = []
    var error: String?
    var refreshedAt = Date()
}
