import Foundation

struct ActionsRunnerConfig: Identifiable {
  let id: String
  let title: String
  let root: String
  let scope: ActionsRunnerScope
  let requiredLabels: [String]
  let serviceLabel: String?

  var runnerConfigurationPath: String {
    root + "/.runner"
  }
}

enum ActionsRunnerScope {
  case organization(String)
  case personalAccount(String)
  case repository(String)

  var description: String {
    switch self {
    case .organization(let organization):
      "\(organization) organization"
    case .personalAccount(let account):
      "\(account) personal repos"
    case .repository(let slug):
      slug
    }
  }
}
