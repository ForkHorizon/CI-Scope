import Foundation
import SwiftUI

@MainActor
extension ContentView {
    var selectedProject: CIProject? {
        projectStore.selectedProject
    }

    var isRefreshing: Bool {
        switch workspaceTab {
        case .projects:
            guard let selectedProject else { return false }
            return projectCIViewModel.loadingProjectID == selectedProject.id
        case .runners:
            return runnerFleetViewModel.isLoading
        case .scripts, .coverage:
            return false
        case .settings:
            return false
        }
    }

    var refreshedAt: Date? {
        switch workspaceTab {
        case .projects:
            guard let selectedProject else { return nil }
            return projectCIViewModel.snapshot(for: selectedProject.id)?.refreshedAt
        case .runners:
            return runnerFleetViewModel.snapshot.refreshedAt
        case .scripts, .coverage:
            return nil
        case .settings:
            return nil
        }
    }

    var canRefresh: Bool {
        switch workspaceTab {
        case .projects:
            selectedProject != nil
        case .runners:
            true
        case .scripts, .coverage:
            false
        case .settings:
            false
        }
    }

    var headerSubtitle: String {
        switch workspaceTab {
        case .projects:
            selectedProject?.repositorySlug ?? "No project selected"
        case .runners:
            "Runner · MacBook"
        case .scripts:
            "\(scriptStore.scripts.count) installable scripts"
        case .coverage:
            "\(projectStore.projects.count) repositories"
        case .settings:
            settingsStore.serverModeEnabled ? "Server queue enabled" : "Server queue off"
        }
    }

    var headerTitle: String {
        switch workspaceTab {
        case .projects:
            selectedProject?.title ?? "Projects"
        case .runners:
            "Runners"
        case .scripts:
            "Scripts"
        case .coverage:
            "Coverage"
        case .settings:
            "Settings"
        }
    }

    var headerIcon: String {
        switch workspaceTab {
        case .projects:
            "square.grid.2x2"
        case .runners:
            "server.rack"
        case .scripts:
            "curlybraces.square"
        case .coverage:
            "tablecells"
        case .settings:
            "gearshape"
        }
    }

    var headerState: ServiceState {
        switch workspaceTab {
        case .projects:
            guard let selectedProject else { return .unknown }
            return state(for: selectedProject)
        case .runners:
            return runnerFleetViewModel.snapshot.state
        case .scripts:
            return scriptStore.scripts.isEmpty ? .unknown : .online
        case .coverage:
            return .unknown
        case .settings:
            return settingsStore.serverModeEnabled ? .online : .unknown
        }
    }

    func state(for project: CIProject) -> ServiceState {
        projectCIViewModel.snapshot(for: project.id)?.state ?? .unknown
    }

    func selectProject(_ project: CIProject) {
        workspaceTab = .projects
        projectStore.select(project)
    }

    func removeProject(_ project: CIProject) {
        projectStore.removeProject(project)
        projectCIViewModel.removeSnapshot(for: project.id)
        scriptInstallViewModel.clearCompletedRemovalSnapshots(for: project)
    }

    func refreshSelectedProject(clearCompletedScriptOperations: Bool = false) {
        guard let selectedProject else { return }

        if clearCompletedScriptOperations {
            scriptInstallViewModel.clearCompletedRemovalSnapshots(for: selectedProject)
        }

        Task {
            await projectCIViewModel.load(selectedProject)
        }
    }

    func refreshSelectedProjectRunnerStatusFromBroker() async {
        guard let selectedProject else { return }
        await projectCIViewModel.refreshLocalRunnerFromBroker(selectedProject)
    }

    func isBrokerManaged(_ project: CIProject) -> Bool {
        LocalBrokerService(config: DashboardConfig()).isManaged(project: project)
    }

    func attachToBroker(_ project: CIProject) {
        Task {
            try? await LocalBrokerService(config: DashboardConfig()).attach(project: project)
            await projectCIViewModel.load(project)
            await runnerFleetViewModel.load()
        }
    }

    func refreshCurrentTab() {
        switch workspaceTab {
        case .projects:
            refreshSelectedProject(clearCompletedScriptOperations: true)
        case .runners:
            Task {
                await runnerFleetViewModel.load()
            }
        case .scripts, .coverage:
            break
        case .settings:
            break
        }
    }
}
