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
