import AppKit
import Combine
import SwiftUI

@MainActor
struct ContentView: View {
    @StateObject var projectStore = ProjectStore()
    @StateObject var projectCIViewModel = ProjectCIViewModel()
    @StateObject var scriptStore = AutomationScriptStore()
    @StateObject var scriptInstallViewModel = AutomationScriptInstallViewModel()
    @StateObject var runnerFleetViewModel = RunnerFleetViewModel()
    @StateObject var settingsStore = CIQueueSettingsStore()
    @StateObject var notificationManager = NotificationManager.shared
    @State var workspaceTab: WorkspaceTab = .projects
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
        .overlay(alignment: .topTrailing) {
            JobNotificationOverlay(manager: notificationManager)
                .allowsHitTesting(notificationManager.activeJobNotification != nil)
        }
        .animation(.easeInOut(duration: 0.18), value: isProjectMenuOpen)
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: notificationManager.activeJobNotification?.id)
        .task(id: selectedProject?.id) {
            guard let selectedProject else { return }
            await projectCIViewModel.load(selectedProject)
        }
        .task(id: workspaceTab) {
            if workspaceTab == .runners {
                await runnerFleetViewModel.load(projects: projectStore.projects)
            }
        }
        .task {
            settingsStore.startV2Lifecycle()
            runnerFleetViewModel.startLiveUpdates {
                await runnerFleetViewModel.load(projects: projectStore.projects)
                await refreshSelectedProjectRunnerStatus()
            }
        }
        .onDisappear {
            runnerFleetViewModel.stopLiveUpdates()
            settingsStore.stopV2Lifecycle()
        }
        .sheet(isPresented: $isAddingProject) {
            AddProjectSheet { input in
                try projectStore.addProject(from: input)
            }
        }
        .onReceive(Timer.publish(every: 10, on: .main, in: .common).autoconnect()) { _ in
            Task { @MainActor in
                // Fallback poll only: skip entirely while GitHub is rate-limited
                // so we never pile requests onto an exhausted quota.
                if await GitHubRateLimitGate.shared.isPaused() { return }
                refreshCurrentTab()
            }
        }
    }
}
