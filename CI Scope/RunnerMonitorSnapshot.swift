import Foundation

struct RunnerMonitorSnapshot: Identifiable {
  let id: String
  let title: String
  let scope: String
  var state: ServiceState = .unknown
  var localState: ServiceState = .unknown
  var githubState: ServiceState = .unknown
  var launchctlState = "unknown"
  var pid: Int?
  var uptime = "-"
  var remoteName = "-"
  var remoteStatus = "unknown"
  var isBusy = false
  var registeredTo = "-"
  var labels: [String] = []
  var missingLabels: [String] = []
  var activeJobs: [RunnerWorkItem] = []
  var queuedJobs: [RunnerWorkItem] = []
  var subRunners: [RunnerSubRunnerSnapshot] = []
  var webhook: BrokerWebhookStatus?
  var error: String?
}

struct RunnerSubRunnerSnapshot: Identifiable {
  let id: String
  let title: String
  let scope: String
  let labels: [String]
  var state: ServiceState
  var visibleRepositoryCount: Int
  var queuedJobCount: Int
  var activeJobCount: Int
  var lastError: String?
}
