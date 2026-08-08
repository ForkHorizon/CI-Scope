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

extension Substring {
    var nilIfEmpty: Substring? {
        isEmpty ? nil : self
    }
}
