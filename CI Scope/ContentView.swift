// Root of the app: the project list on the left, and the project, alerts or settings on the right.
import AppKit
import SwiftUI

@MainActor
struct ContentView: View {
    @StateObject var projectStore = ProjectStore()
    @StateObject var settingsStore = CIQueueSettingsStore()
    @StateObject var protection = ProjectProtectionViewModel()
    @StateObject var securityEvents = SecurityEventMonitor()
    @StateObject var gateJobs = GateJobsMonitor()
    @State var workspaceTab: WorkspaceTab = .projects
    @State var isAddingProject = false

    var body: some View {
        HStack(spacing: 0) {
            ProjectMenuPanel(
                workspaceTab: $workspaceTab,
                projects: projectStore.projects,
                selectedProjectID: projectStore.selectedProjectID,
                alertCount: securityEvents.events.count,
                activeTaskCount: gateJobs.activeCount,
                stateForProject: state(for:),
                onSelect: selectProject,
                onAddProject: { isAddingProject = true }
            )
            VStack(spacing: 0) {
                header
                content
                    .id(workspaceTab)
                    .transition(.opacity)
            }
            .animation(.smooth(duration: 0.2), value: workspaceTab)
            .frame(minWidth: 520, maxWidth: .infinity)
        }
        .frame(minWidth: 760, idealWidth: 860, minHeight: 560, idealHeight: 620)
        .background(NothingTheme.canvas)
        .task {
            ToastCenter.shared.onOpen = { tab in
                workspaceTab = tab
                NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
            }
            settingsStore.startV2Lifecycle()
            while !Task.isCancelled {
                await refreshProjects()
                await securityEvents.refresh()
                await gateJobs.refresh()
                try? await Task.sleep(for: .seconds(10))
            }
        }
        .onDisappear { settingsStore.stopV2Lifecycle() }
        .sheet(isPresented: $isAddingProject) {
            AddProjectSheet { input in
                let project = try projectStore.addProject(from: input)
                workspaceTab = .projects
                Task {
                    await protection.register(repository: project.repositorySlug)
                    await refreshProjects()
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch workspaceTab {
        case .projects:
            if let project = projectStore.selectedProject {
                ProjectDetailView(project: project, model: protection, events: securityEvents)
            } else {
                EmptyProjectDashboard { isAddingProject = true }
            }
        case .activity:
            ActivityView(monitor: gateJobs)
        case .alerts:
            AlertsView(events: securityEvents)
        case .settings:
            SettingsView(store: settingsStore, v2Control: settingsStore.v2Control)
        }
    }

    /// The sidebar mirrors the server's registered projects; a failed read keeps the list as it is.
    private func refreshProjects() async {
        guard let token = try? await ServerAuthorizer.configReadToken(),
              let slugs = try? await ProjectConfigClient().listRepositories(readToken: token) else { return }
        projectStore.sync(with: slugs)
    }

    private func state(for project: CIProject) -> ServiceState {
        securityEvents.events.contains { $0.repository.caseInsensitiveCompare(project.repositorySlug) == .orderedSame }
            ? .warning : .unknown
    }

    private func selectProject(_ project: CIProject) {
        workspaceTab = .projects
        projectStore.select(project)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(headerTitle).nothingDisplay(26).foregroundStyle(NothingTheme.ink).lineLimit(1)
                .id(headerTitle).transition(.opacity.combined(with: .offset(y: -6)))
            Text(headerSubtitle).nothingCaption().lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { Rectangle().fill(NothingTheme.line).frame(height: 1) }
        .animation(.smooth(duration: 0.3), value: headerTitle)
    }

    private var headerTitle: String {
        workspaceTab == .projects ? (projectStore.selectedProject?.title ?? "Projects") : workspaceTab.title
    }

    private var headerSubtitle: String {
        switch workspaceTab {
        case .projects: projectStore.selectedProject?.repositorySlug ?? "No project selected"
        case .activity: gateJobs.activeCount == 0 ? "Idle" : "\(gateJobs.activeCount) in progress or waiting"
        case .alerts: securityEvents.events.isEmpty ? "Nothing needs your attention" : "\(securityEvents.events.count) open"
        case .settings: "This Mac and the website"
        }
    }
}
