import AppKit
import SwiftUI

struct ContentView: View {
    @StateObject var viewModel = DashboardViewModel()
    @StateObject var projectStore = ProjectStore()
    @StateObject var projectCIViewModel = ProjectCIViewModel()
    @StateObject var readabilityGateInstaller = ReadabilityGateInstallViewModel()
    @StateObject var runnerFleetViewModel = RunnerFleetViewModel()
    @State var workspaceTab: WorkspaceTab = .projects
    @State var section: DashboardSection = .runs
    @State var isProjectMenuOpen = true
    @State var isAddingProject = false

    var body: some View {
        HStack(spacing: 0) {
            if isProjectMenuOpen {
                ProjectMenuPanel(
                    workspaceTab: $workspaceTab,
                    projects: projectStore.projects,
                    selectedProjectID: projectStore.selectedProjectID,
                    stateForProject: state(for:),
                    runnerState: runnerFleetViewModel.snapshot.state,
                    runnerCount: runnerFleetViewModel.snapshot.runners.count,
                    onSelect: selectProject,
                    onRemove: removeProject,
                    onAddProject: {
                        isAddingProject = true
                    }
                )
                    .transition(.move(edge: .leading).combined(with: .opacity))
                Divider()
            }
            dashboardSurface
        }
        .frame(
            minWidth: isProjectMenuOpen ? 792 : 587,
            idealWidth: isProjectMenuOpen ? 792 : 587,
            minHeight: 624,
            idealHeight: 624
        )
        .background(Color(nsColor: .windowBackgroundColor))
        .animation(.easeInOut(duration: 0.18), value: isProjectMenuOpen)
        .task(id: selectedProject?.id) {
            guard let selectedProject else { return }
            await projectCIViewModel.load(selectedProject)
            if isLocalToolsProject(selectedProject) {
                viewModel.refresh()
            }
        }
        .task(id: workspaceTab) {
            if workspaceTab == .runners {
                await runnerFleetViewModel.load()
            }
        }
        .sheet(isPresented: $isAddingProject) {
            AddProjectSheet { input in
                try projectStore.addProject(from: input)
            }
        }
    }
}
