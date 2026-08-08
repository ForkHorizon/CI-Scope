import Foundation

struct BrokerJob: Identifiable, Codable, Equatable {
    var id: String
    var repositorySlug: String
    var workflowName: String
    var title: String
    var jobName: String
    var headBranch: String
    var status: String
    var url: String
    var createdAt: String
    var labels: [String]
    var runId: Int64?
    var jobId: Int64?
    var profileID: String?
    var profileTitle: String?
    var profileScope: String?
    var progress: BrokerJobProgress?

    var workItem: RunnerWorkItem {
        RunnerWorkItem(
            id: id,
            repositorySlug: repositorySlug,
            workflowName: workflowName,
            title: title,
            jobName: jobName,
            headBranch: headBranch,
            status: status,
            url: url,
            assemblerTitle: profileTitle,
            assemblerScope: profileScope,
            progress: progress
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case repositorySlug
        case workflowName
        case title
        case jobName
        case headBranch
        case status
        case url
        case createdAt
        case labels
        case runId
        case jobId
        case profileID = "profileId"
        case profileTitle
        case profileScope
        case progress
    }
}
