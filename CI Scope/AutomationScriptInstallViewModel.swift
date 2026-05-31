import Foundation
import Combine

@MainActor
final class AutomationScriptInstallViewModel: ObservableObject {
    @Published private var snapshots: [String: AutomationScriptInstallSnapshot] = [:]

    private let installer: AutomationScriptInstaller

    init() {
        self.installer = AutomationScriptInstaller(config: DashboardConfig())
    }

    init(config: DashboardConfig) {
        self.installer = AutomationScriptInstaller(config: config)
    }

    func snapshot(for script: AutomationScript?) -> AutomationScriptInstallSnapshot {
        guard let script else { return .idle }
        return snapshots[script.id] ?? .idle
    }

    func install(
        script: AutomationScript,
        project: CIProject?,
        variableValues: [String: String],
        onSuccess: @escaping () -> Void = {}
    ) {
        guard !snapshots.values.contains(where: \.isInstalling) else { return }
        guard let project else {
            snapshots[script.id] = .failed(AutomationScriptError.missingProject.localizedDescription)
            return
        }

        snapshots[script.id] = .installing(script)
        Task {
            do {
                let result = try await installer.install(
                    script: script,
                    project: project,
                    variableValues: variableValues
                )
                snapshots[script.id] = .succeeded(result)
                onSuccess()
            } catch {
                snapshots[script.id] = .failed(error.localizedDescription)
            }
        }
    }
}
