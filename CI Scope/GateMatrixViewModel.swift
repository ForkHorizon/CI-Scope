import Combine
import Foundation

/// Loads each project's default-branch workflow files so the coverage matrix can
/// show which managed gates are installed where. Detection itself is the same
/// `AutomationScript.matchingWorkflow` the rest of the app uses; only the source
/// is narrower, because a gate sitting in an unmerged install PR is not installed.
@MainActor
final class GateMatrixViewModel: ObservableObject {
    @Published private(set) var workflowsByProject: [String: [GitHubWorkflow]] = [:]
    @Published private(set) var isLoading = false

    private let service = ProjectCIService(config: DashboardConfig())

    func load(_ projects: [CIProject]) async {
        isLoading = true
        var result: [String: [GitHubWorkflow]] = [:]
        for project in projects {
            result[project.id] = await service.defaultBranchWorkflows(for: project)
        }
        workflowsByProject = result
        isLoading = false
    }

    func isInstalled(_ script: AutomationScript, projectID: String) -> Bool {
        var snapshot = ProjectCISnapshot()
        snapshot.workflows = workflowsByProject[projectID] ?? []
        return script.matchingWorkflow(in: snapshot) != nil
    }
}
