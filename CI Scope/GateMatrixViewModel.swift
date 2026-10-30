import Combine
import Foundation

enum GatePresence: Equatable {
    case installed
    case missing
    case unknown
}

/// Reads default-branch workflows and the unified manifest. An unmerged install
/// PR is not installed, and an API failure is not evidence that a gate is missing.
@MainActor
final class GateMatrixViewModel: ObservableObject {
    @Published private(set) var workflowsByProject: [String: [GitHubWorkflow]] = [:]
    @Published private(set) var manifestsByProject: [String: CIScopeManifest] = [:]
    @Published private(set) var unknownProjects: Set<String> = []
    @Published private(set) var isLoading = false

    private let service = ProjectCIService(config: DashboardConfig())

    func load(_ projects: [CIProject]) async {
        isLoading = true
        var result: [String: [GitHubWorkflow]] = [:]
        var manifests: [String: CIScopeManifest] = [:]
        var unknown: Set<String> = []
        for project in projects {
            async let workflows = service.defaultBranchWorkflows(for: project)
            async let manifest = service.loadUnifiedManifest(for: project)
            let workflowResponse = await workflows
            let manifestResponse = await manifest
            result[project.id] = workflowResponse.value ?? []
            manifests[project.id] = manifestResponse.value
            if workflowResponse.error != nil || manifestResponse.error != nil {
                unknown.insert(project.id)
            }
        }
        workflowsByProject = result
        manifestsByProject = manifests
        unknownProjects = unknown
        isLoading = false
    }

    func presence(_ script: AutomationScript, projectID: String) -> GatePresence {
        guard let workflows = workflowsByProject[projectID] else { return .unknown }
        return Self.presence(
            script, workflows: workflows, manifest: manifestsByProject[projectID],
            lookupFailed: unknownProjects.contains(projectID))
    }

    static func presence(
        _ script: AutomationScript, workflows: [GitHubWorkflow],
        manifest: CIScopeManifest?, lookupFailed: Bool
    ) -> GatePresence {
        var snapshot = ProjectCISnapshot()
        snapshot.workflows = workflows
        if script.matchingWorkflow(in: snapshot) != nil { return .installed }
        let unifiedExists = workflows.contains {
            $0.path?.lowercased() == ".github/workflows/ci-scope-checks.yml"
        }
        let checkType = (script.defaultSeedID ?? script.id).replacingOccurrences(of: "-gate", with: "")
        if unifiedExists, manifest?.checks.contains(where: { $0.type == checkType }) == true {
            return .installed
        }
        return lookupFailed ? .unknown : .missing
    }
}
