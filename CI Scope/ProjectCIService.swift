import Foundation

struct ProjectCIService {
    let config: DashboardConfig

    func loadSnapshot(for project: CIProject) async -> ProjectCISnapshot {
        async let authResult = loadAuthStatus()
        async let workflowsResult = loadWorkflows(for: project)
        async let runsResult = loadRuns(for: project)
        async let localRunnerResult = loadLocalRunner(for: project)

        let authResponse = await authResult
        let workflowResponse = await workflowsResult
        let runResponse = await runsResult
        let localRunnerResponse = await localRunnerResult

        var snapshot = ProjectCISnapshot(projectID: project.id)
        snapshot.localRunner = localRunnerResponse
        snapshot.workflows = workflowResponse.value ?? []
        snapshot.runs = runResponse.value ?? []
        snapshot.refreshedAt = Date()

        var errors = [workflowResponse.error, runResponse.error].compactMap { $0 }
        if !errors.isEmpty {
            if authResponse.state == .offline, let detail = authResponse.detail {
                errors.insert("GitHub CLI auth:\n\(detail)", at: 0)
            }
            snapshot.state = snapshot.workflows.isEmpty && snapshot.runs.isEmpty ? .offline : .warning
            snapshot.error = errors.joined(separator: "\n\n")
            return snapshot
        }

        snapshot.state = state(workflows: snapshot.workflows, runs: snapshot.runs)
        return snapshot
    }
}
