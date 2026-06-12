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

    var visibleRepositoryCount: Int {
        runners.reduce(0) { $0 + $1.visibleRepositoryCount }
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
    let root: String
    var state: ServiceState = .unknown
    var localState: ServiceState = .unknown
    var githubState: ServiceState = .unknown
    var serviceLabel: String?
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
    var visibleRepositoryCount = 0
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
    let createdAt: String
    let labels: [String]
    let assemblerID: String?
    let assemblerTitle: String?
    let assemblerScope: String?

    init(
        id: String,
        repositorySlug: String,
        workflowName: String,
        title: String,
        jobName: String,
        headBranch: String,
        status: String,
        url: String,
        createdAt: String,
        labels: [String],
        assemblerID: String? = nil,
        assemblerTitle: String? = nil,
        assemblerScope: String? = nil
    ) {
        self.id = id
        self.repositorySlug = repositorySlug
        self.workflowName = workflowName
        self.title = title
        self.jobName = jobName
        self.headBranch = headBranch
        self.status = status
        self.url = url
        self.createdAt = createdAt
        self.labels = labels
        self.assemblerID = assemblerID
        self.assemblerTitle = assemblerTitle
        self.assemblerScope = assemblerScope
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
    let error: String?
}

struct FleetRunnerConfiguration: Decodable {
    let agentName: String?
    let gitHubUrl: String?
}

struct FleetLocalRunnerInfo {
    let config: ActionsRunnerConfig
    let runner: FleetRunnerConfiguration
    let repositorySlug: String?
    let owner: String?

    var registrationLabel: String {
        repositorySlug ?? owner ?? config.scope.description
    }
}

struct FleetGitHubRunnerList: Decodable {
    let runners: [FleetGitHubActionsRunner]
}

struct FleetGitHubActionsRunner: Decodable {
    let name: String
    let status: String
    let busy: Bool
    let labels: [FleetGitHubRunnerLabel]

    func hasLabels(_ requiredLabels: [String]) -> Bool {
        let availableLabels = Set(labels.map { $0.name.lowercased() })
        return requiredLabels.allSatisfy { availableLabels.contains($0.lowercased()) }
    }
}

struct FleetGitHubRunnerLabel: Decodable {
    let name: String
}

struct WorkflowRunContext {
    let id: Int64
    let repositorySlug: String
    let workflowName: String
    let displayTitle: String
    let headBranch: String
    let status: String
    let conclusion: String?
    let url: String
    let createdAt: String
}

struct WorkflowJob: Decodable {
    let id: Int64
    let name: String
    let status: String
    let runnerName: String?
    let htmlURL: String?
    let labels: [String]
    let workflowName: String?
    let createdAt: String?
    let startedAt: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case status
        case runnerName = "runner_name"
        case htmlURL = "html_url"
        case labels
        case workflowName = "workflow_name"
        case createdAt = "created_at"
        case startedAt = "started_at"
    }
}

struct JobContext {
    let run: WorkflowRunContext
    let job: WorkflowJob
}

struct FleetLoadResponse<Value> {
    var value: Value?
    var error: String?
}
