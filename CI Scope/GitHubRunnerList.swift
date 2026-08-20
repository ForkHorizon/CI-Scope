import Foundation

struct LocalRunnerInfo {
  let config: ActionsRunnerConfig
  let runner: RunnerConfiguration
  let repositorySlug: String?
  let owner: String?
}

struct GitHubRunnerList: Decodable {
  let runners: [GitHubActionsRunner]
}
