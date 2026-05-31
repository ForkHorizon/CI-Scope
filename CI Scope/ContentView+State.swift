import Foundation
import SwiftUI

extension ContentView {
    var runnerDetail: String {
        let pid = viewModel.snapshot.runner.listenerPID ?? viewModel.snapshot.runner.servicePID
        return "PID \(pid.map(String.init) ?? "-") · \(viewModel.snapshot.runner.uptime)"
    }

    var ollamaDetail: String {
        guard let model = viewModel.snapshot.ollama.loadedModels.first else {
            return "\(viewModel.snapshot.ollama.availableModels.count) models"
        }

        let bytes = model.sizeVRAM ?? model.size ?? 0
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .memory)
    }

    var unityDetail: String {
        let pid = viewModel.snapshot.nexusUnity.status?.processId.map(String.init) ?? "-"
        let version = viewModel.snapshot.nexusUnity.status?.unityVersion ?? "-"
        return "PID \(pid) · \(version)"
    }

    var latestRunState: ServiceState {
        guard let run = viewModel.snapshot.runs.first else { return .unknown }
        if run.conclusion == "success" { return .online }
        if run.status != "completed" { return .warning }
        return .offline
    }

    var selectedProject: CIProject? {
        projectStore.selectedProject
    }

    var isRefreshing: Bool {
        switch workspaceTab {
        case .projects:
            guard let selectedProject else { return false }
            return projectCIViewModel.loadingProjectID == selectedProject.id || (isLocalToolsProject(selectedProject) && viewModel.isRefreshing)
        case .runners:
            return runnerFleetViewModel.isLoading
        case .scripts:
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
        case .scripts:
            return nil
        }
    }

    var canRefresh: Bool {
        switch workspaceTab {
        case .projects:
            selectedProject != nil
        case .runners:
            true
        case .scripts:
            false
        }
    }

    var headerSubtitle: String {
        switch workspaceTab {
        case .projects:
            selectedProject?.repositorySlug ?? "No project selected"
        case .runners:
            "Runners · \(runnerFleetViewModel.snapshot.runners.count) configured"
        case .scripts:
            "\(scriptStore.scripts.count) installable scripts"
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
    }

    func refreshSelectedProject() {
        guard let selectedProject else { return }

        Task {
            await projectCIViewModel.load(selectedProject)
        }

        if isLocalToolsProject(selectedProject) {
            viewModel.refresh()
        }
    }

    func refreshCurrentTab() {
        switch workspaceTab {
        case .projects:
            refreshSelectedProject()
        case .runners:
            Task {
                await runnerFleetViewModel.load()
            }
        case .scripts:
            break
        }
    }

    func isLocalToolsProject(_ project: CIProject) -> Bool {
        project.normalizedSlug == viewModel.config.repositorySlug.lowercased()
    }
}
