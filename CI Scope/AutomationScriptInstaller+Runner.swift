import Foundation

extension AutomationScriptInstaller {
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

        return script.runnerLabels
    }
}
