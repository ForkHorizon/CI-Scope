import Foundation

struct InstalledAutomationScript: Identifiable {
    let script: AutomationScript
    let workflow: GitHubWorkflow

    var id: String {
        "\(script.id):\(workflow.path ?? workflow.id)"
    }

    var state: ServiceState {
        workflow.state.lowercased().contains("disabled") ? .warning : .online
    }

    var title: String {
        workflow.name
    }

    var detail: String {
        guard let path = workflow.path, !path.isEmpty else {
            return script.title
        }
        if workflow.name == script.title {
            return path
        }
        return "\(path) · Library: \(script.title)"
    }
}

extension AutomationScript {
    var workflowDestinationPaths: Set<String> {
        var paths = Set(
            files
                .map { renderedDetectionPath($0.destinationPath).normalizedRepositoryPath }
                .filter { path in
                    path.hasPrefix(".github/workflows/")
                        && (path.hasSuffix(".yml") || path.hasSuffix(".yaml"))
                        && !path.contains("{{")
                }
        )

        if managesLegacyReadabilityInstall {
            paths.insert(".github/workflows/ai-readability.yml")
        }

        return paths
    }

    func matchingWorkflow(in snapshot: ProjectCISnapshot?) -> GitHubWorkflow? {
        guard let snapshot else { return nil }
        let scriptWorkflowPaths = workflowDestinationPaths
        guard !scriptWorkflowPaths.isEmpty else { return nil }

        return snapshot.workflows.first { workflow in
            guard let path = workflow.path?.normalizedRepositoryPath else { return false }
            return scriptWorkflowPaths.contains(path)
        }
    }

    private func renderedDetectionPath(_ path: String) -> String {
        path
            .replacingOccurrences(of: "{{script_id}}", with: id)
            .replacingOccurrences(of: "{{script_slug}}", with: scriptSlug)
            .replacingOccurrences(of: "{{script_title}}", with: title)
    }

    private var managesLegacyReadabilityInstall: Bool {
        defaultSeedID == "ai-readability" || id == "ai-readability"
    }
}

private extension String {
    var normalizedRepositoryPath: String {
        trimmed
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
    }
}
