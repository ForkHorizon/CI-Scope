import Foundation
import Combine

@MainActor
final class AutomationScriptInstallViewModel: ObservableObject {
    @Published private var snapshots: [String: AutomationScriptInstallSnapshot] = [:]

    private let installer: AutomationScriptInstaller

    init() {
        self.installer = AutomationScriptInstaller(config: DashboardConfig())
    }

    func snapshot(for script: AutomationScript?) -> AutomationScriptInstallSnapshot {
        guard let script else { return .idle }
        return snapshots[installKey(script)] ?? .idle
    }

    func removalSnapshot(for script: AutomationScript, project: CIProject) -> AutomationScriptInstallSnapshot {
        snapshots[removeKey(script, project: project)] ?? .idle
    }

    func install(
        script: AutomationScript,
        project: CIProject?,
        variableValues: [String: String],
        mode: AutomationScriptInstallMode,
        onSuccess: @escaping () -> Void = {}
    ) {
        guard !snapshots.values.contains(where: \.isInstalling) else { return }
        let snapshotKey = installKey(script)
        guard let project else {
            snapshots[snapshotKey] = .failed(AutomationScriptError.missingProject.localizedDescription)
            return
        }

        snapshots[snapshotKey] = .installing(script)
        Task {
            do {
                let result = try await installer.install(
                    script: script,
                    project: project,
                    variableValues: variableValues,
                    mode: mode
                )
                ProjectCIService.invalidateWorkflowsCache(forRepositorySlug: project.repositorySlug)
                snapshots[snapshotKey] = .succeeded(result)
                onSuccess()
            } catch {
                snapshots[snapshotKey] = .failed(error.localizedDescription)
            }
        }
    }

    func installBundle(
        scripts: [AutomationScript],
        project: CIProject?,
        mode: AutomationScriptInstallMode,
        onSuccess: @escaping () -> Void = {}
    ) {
        guard !snapshots.values.contains(where: \.isInstalling) else { return }
        let snapshotKey = bundleKey(project)
        guard let project else {
            snapshots[snapshotKey] = .failed(AutomationScriptError.missingProject.localizedDescription)
            return
        }
        guard !scripts.isEmpty else { return }

        snapshots[snapshotKey] = .installingBundle(count: scripts.count)
        Task {
            do {
                let result = try await installer.installBundle(scripts: scripts, project: project, mode: mode)
                ProjectCIService.invalidateWorkflowsCache(forRepositorySlug: project.repositorySlug)
                snapshots[snapshotKey] = .succeeded(result)
                onSuccess()
            } catch {
                snapshots[snapshotKey] = .failed(error.localizedDescription)
            }
        }
    }

    func bundleSnapshot(for project: CIProject) -> AutomationScriptInstallSnapshot {
        snapshots[bundleKey(project)] ?? .idle
    }

    func remove(
        script: AutomationScript,
        project: CIProject?,
        onSuccess: @escaping () -> Void = {}
    ) {
        guard !snapshots.values.contains(where: \.isInstalling) else { return }
        guard let project else { return }
        let snapshotKey = removeKey(script, project: project)
        snapshots[snapshotKey] = .removing(script)
        Task {
            do {
                let result = try await installer.remove(
                    script: script,
                    project: project,
                    variableValues: defaultValues(for: script)
                )
                ProjectCIService.invalidateWorkflowsCache(forRepositorySlug: project.repositorySlug)
                snapshots[snapshotKey] = .succeeded(result)
                onSuccess()
            } catch {
                snapshots[snapshotKey] = .failed(error.localizedDescription)
            }
        }
    }

    func clearCompletedRemovalSnapshots(for project: CIProject) {
        let prefix = "remove:\(project.id):"
        snapshots = snapshots.filter { key, snapshot in
            !key.hasPrefix(prefix) || snapshot.isInstalling
        }
    }

    private func defaultValues(for script: AutomationScript) -> [String: String] {
        Dictionary(uniqueKeysWithValues: script.variables.map { ($0.id, $0.defaultValue) })
    }

    private func installKey(_ script: AutomationScript) -> String {
        "install:\(script.id)"
    }

    private func bundleKey(_ project: CIProject?) -> String {
        "bundle:\(project?.id ?? "-")"
    }

    private func removeKey(_ script: AutomationScript, project: CIProject) -> String {
        "remove:\(project.id):\(script.id)"
    }
}
