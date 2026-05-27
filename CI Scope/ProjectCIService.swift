import Foundation

struct ProjectCIService {
    let config: DashboardConfig

    func loadSnapshot(for project: CIProject) async -> ProjectCISnapshot {
        async let workflowsResult = loadWorkflows(for: project)
        async let runsResult = loadRuns(for: project)

        let workflowResponse = await workflowsResult
        let runResponse = await runsResult

        var snapshot = ProjectCISnapshot(projectID: project.id)
        snapshot.workflows = workflowResponse.value ?? []
        snapshot.runs = runResponse.value ?? []
        snapshot.refreshedAt = Date()

        let errors = [workflowResponse.error, runResponse.error].compactMap { $0 }
        if !errors.isEmpty {
            snapshot.state = .offline
            snapshot.error = errors.joined(separator: "\n")
            return snapshot
        }

        snapshot.state = state(workflows: snapshot.workflows, runs: snapshot.runs)
        return snapshot
    }

    private func loadWorkflows(for project: CIProject) async -> LoadResponse<[GitHubWorkflow]> {
        let command = """
        gh workflow list --repo \(quoted(project.repositorySlug)) --all --limit 100 --json id,name,path,state
        """
        let result = await ShellClient.run(command, timeout: 15, config: config)
        guard result.exitCode == 0, let data = result.output.data(using: .utf8) else {
            return LoadResponse(error: trimmedError(result.output, fallback: "Failed to load workflows."))
        }

        do {
            return LoadResponse(value: try JSONDecoder().decode([GitHubWorkflow].self, from: data))
        } catch {
            return LoadResponse(error: error.localizedDescription)
        }
    }

    private func loadRuns(for project: CIProject) async -> LoadResponse<[GitHubRun]> {
        let command = """
        gh run list --repo \(quoted(project.repositorySlug)) --limit 20 --json databaseId,status,conclusion,displayTitle,workflowName,headBranch,event,createdAt,updatedAt,url
        """
        let result = await ShellClient.run(command, timeout: 15, config: config)
        guard result.exitCode == 0, let data = result.output.data(using: .utf8) else {
            return LoadResponse(error: trimmedError(result.output, fallback: "Failed to load workflow runs."))
        }

        do {
            return LoadResponse(value: try JSONDecoder().decode([GitHubRun].self, from: data))
        } catch {
            return LoadResponse(error: error.localizedDescription)
        }
    }

    private func state(workflows: [GitHubWorkflow], runs: [GitHubRun]) -> ServiceState {
        guard let latestRun = runs.first else {
            return workflows.isEmpty ? .unknown : .online
        }

        if latestRun.status != "completed" {
            return .warning
        }

        return latestRun.conclusion == "success" ? .online : .offline
    }

    private func trimmedError(_ output: String, fallback: String) -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func quoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

private struct LoadResponse<Value> {
    var value: Value?
    var error: String?
}
