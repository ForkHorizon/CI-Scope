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

struct RunnerWorkItem: Identifiable {
    let id: String
    let repositorySlug: String
    let workflowName: String
    let title: String
    let jobName: String
    let headBranch: String
    let status: String
    let url: String
    let assemblerTitle: String?
    let assemblerScope: String?
    let progress: BrokerJobProgress?

    init(
        id: String,
        repositorySlug: String,
        workflowName: String,
        title: String,
        jobName: String,
        headBranch: String,
        status: String,
        url: String,
        assemblerTitle: String? = nil,
        assemblerScope: String? = nil,
        progress: BrokerJobProgress? = nil
    ) {
        self.id = id
        self.repositorySlug = repositorySlug
        self.workflowName = workflowName
        self.title = title
        self.jobName = jobName
        self.headBranch = headBranch
        self.status = status
        self.url = url
        self.assemblerTitle = assemblerTitle
        self.assemblerScope = assemblerScope
        self.progress = progress
    }
}

struct BrokerWebhookStatus: Codable, Equatable {
    var enabled: Bool
    var port: Int?
    var path: String?
    var lastDeliveryAt: String?
    var lastDeliveryID: String?
    var lastAction: String?
    var lastRepository: String?
    var lastJob: String?
    var lastError: String?

    private enum CodingKeys: String, CodingKey {
        case enabled
        case port
        case path
        case lastDeliveryAt
        case lastDeliveryID = "lastDeliveryId"
        case lastAction
        case lastRepository
        case lastJob
        case lastError
    }
}

struct RunnerLaunchStatus {
    let state: ServiceState
    let launchctlState: String
    let pid: Int?
    let uptime: String
}
