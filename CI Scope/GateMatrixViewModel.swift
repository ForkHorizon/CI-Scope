import Combine
import Foundation

/// Loads each project's workflow list so the coverage matrix can show which
/// managed gates are installed where. Reuses the same detection the rest of the
/// app uses (`AutomationScript.matchingWorkflow`), so results stay consistent.
@MainActor
final class GateMatrixViewModel: ObservableObject {
    @Published private(set) var workflowsByProject: [String: [GitHubWorkflow]] = [:]
    @Published private(set) var isLoading = false

    private let service = ProjectCIService(config: DashboardConfig())

    func load(_ projects: [CIProject], forceRefresh: Bool = false) async {
        isLoading = true
        var result: [String: [GitHubWorkflow]] = [:]
        for project in projects {
            let response = await service.loadWorkflows(for: project, forceRefresh: forceRefresh)
            result[project.id] = response.value ?? []
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
