import Foundation

extension AutomationScriptInstaller {
    func validateRunnerAccessIfNeeded(mode: AutomationScriptInstallMode, project: CIProject)
        async throws
    {
        guard mode == .localRunner else { return }
        let output = try await run(
            "gh repo view \(quoted(project.repositorySlug)) --json viewerPermission",
            timeout: 30,
            step: "Check runner repository access"
        )
        guard let data = output.data(using: .utf8),
            let repo = try? JSONDecoder().decode(RunnerRepositoryAccess.self, from: data)
        else {
            throw AutomationScriptError.invalidValue(
                "Could not read repository permission for MacBook Runner.")
        }
        guard repo.viewerPermission == "ADMIN" else {
            throw AutomationScriptError.invalidValue(
                "MacBook Runner needs admin access to create JIT runners for \(project.repositorySlug).")
        }
    }

    func attachRunnerIfNeeded(mode: AutomationScriptInstallMode, project: CIProject) async throws {
        _ = project
        // In V2, repositories within the organization or enrolled machine scope are handled automatically.
        guard mode == .localRunner else { return }
    }

    func validateRunnerLabelsSatisfiable(
        mode: AutomationScriptInstallMode,
        script: AutomationScript,
        project: CIProject
    ) throws {
        guard mode == .localRunner else { return }
        let settings = CIQueueSettingsStore.snapshot()
        guard settings.serverModeEnabled else { return }
        let machineLabels = Set(settings.labels.map { $0.lowercased() })
        let required = runnerLabels(for: mode, script: script, project: project)
        let missing = required.filter { !machineLabels.contains($0.lowercased()) }
        guard !missing.isEmpty else { return }
        throw AutomationScriptError.invalidValue(
            "MacBook Runner doesn't advertise the label(s) \(missing.joined(separator: ", ")) "
                + "required by \(script.title) (runs-on: \(required.joined(separator: ", "))). "
                + "Add them in Settings \u{2192} Labels first, or this job will queue forever with nothing able to claim it."
        )
    }

    func runnerLabels(
        for mode: AutomationScriptInstallMode,
        script: AutomationScript,
        project: CIProject
    ) -> [String] {
        _ = project
        guard mode == .localRunner else {
            return mode.runnerLabels(for: script)
        }

        return ["self-hosted", "macOS", "ARM64", "ci-scope", "ci-scope-v2"]
    }
}

private struct RunnerRepositoryAccess: Decodable {
    let viewerPermission: String
}
