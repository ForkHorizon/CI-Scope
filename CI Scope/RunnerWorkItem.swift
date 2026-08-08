import Foundation

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
    // The synthesized memberwise init already defaults the optionals to nil,
    // so an explicit 11-parameter init would just restate it.
    let progress: BrokerJobProgress?
}
