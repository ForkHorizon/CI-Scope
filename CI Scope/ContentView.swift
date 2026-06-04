import AppKit
import SwiftUI

struct ContentView: View {
    @StateObject var viewModel = DashboardViewModel()
    @StateObject var projectStore = ProjectStore()
    @StateObject var projectCIViewModel = ProjectCIViewModel()
    @StateObject var scriptStore = AutomationScriptStore()
    @StateObject var scriptInstallViewModel = AutomationScriptInstallViewModel()
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
                    localToolsState: localToolsState,
                    localToolsIssueCount: viewModel.snapshot.errors.count,
                    scriptState: scriptStore.scripts.isEmpty ? .unknown : .online,
                    scriptCount: scriptStore.scripts.count,
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
        }
        .task(id: workspaceTab) {
            if workspaceTab == .runners {
                await runnerFleetViewModel.load()
            } else if workspaceTab == .localTools {
                viewModel.refresh()
            }
        }
        .sheet(isPresented: $isAddingProject) {
            AddProjectSheet { input in
                try projectStore.addProject(from: input)
            }
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
            refreshCurrentTab()
        }
    }
}
