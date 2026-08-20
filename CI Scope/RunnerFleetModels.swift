import Foundation

struct RunnerFleetSnapshot {
  var runners: [RunnerMonitorSnapshot] = []
  var refreshedAt = Date()
  var errors: [String] = []

  var state: ServiceState {
    if runners.isEmpty { return errors.isEmpty ? .unknown : .offline }
    if runners.contains(where: { $0.state == .offline }) { return .offline }
    if runners.contains(where: { $0.state == .warning }) { return .warning }
    if runners.contains(where: { $0.state == .unknown }) { return .unknown }
    return .online
  }

  var activeJobCount: Int {
    runners.reduce(0) { $0 + $1.activeJobs.count }
  }

  var queuedJobCount: Int {
    runners.reduce(0) { $0 + $1.queuedJobs.count }
  }

  var subRunnerCount: Int {
    runners.reduce(0) { $0 + $1.subRunners.count }
  }
}

struct JobArrivalNotification: Identifiable {
  let id: String
  let newJobs: [RunnerWorkItem]
  let runningJobs: [RunnerWorkItem]
  let queuedJobs: [RunnerWorkItem]
  let createdAt: Date

  init(
    newJobs: [RunnerWorkItem],
    runningJobs: [RunnerWorkItem],
    queuedJobs: [RunnerWorkItem],
    createdAt: Date = Date()
  ) {
    // Unique per notification so two arrivals in the same instant don't
    // share a UNNotificationRequest identifier (which would replace, not
    // add, the second banner).
    self.id = UUID().uuidString
    self.newJobs = newJobs
    self.runningJobs = runningJobs
    self.queuedJobs = queuedJobs
    self.createdAt = createdAt
  }
}
