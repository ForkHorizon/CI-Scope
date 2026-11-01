import SwiftUI

struct ProjectMenuPanel: View {
    @Binding var workspaceTab: WorkspaceTab

    let projects: [CIProject]
    let selectedProjectID: CIProject.ID?
    let stateForProject: (CIProject) -> ServiceState
    let runnerState: ServiceState
    let runnerCount: Int
    let scriptState: ServiceState
    let scriptCount: Int
    let policyPendingCount: Int
    let testAlertCount: Int
    let onSelect: (CIProject) -> Void
    let onRemove: (CIProject) -> Void
    let onAddProject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("CI SCOPE")
                .nothingDisplay(24)
                .foregroundStyle(NothingTheme.ink)
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 16)

            VStack(spacing: 3) {
                ForEach(navItems, id: \.tab) { item in
                    WorkspaceMenuRow(
                        tab: item.tab, state: item.state, count: item.count,
                        isActive: workspaceTab == item.tab
                    ) { workspaceTab = item.tab }
                }
            }
            .padding(.horizontal, 10)

            Text("Projects")
                .nothingCaption()
                .padding(.horizontal, 18)
                .padding(.top, 22)
                .padding(.bottom, 6)

            ScrollView {
                LazyVStack(spacing: 2) {
                    if projects.isEmpty {
                        Text("No projects saved").font(.caption).foregroundStyle(NothingTheme.inkDim).padding(8)
                    }
                    ForEach(projects) { project in
                        ProjectMenuRow(
                            project: project,
                            state: stateForProject(project),
                            isActive: workspaceTab == .projects && project.id == selectedProjectID
                        ) { onSelect(project) } onRemove: { onRemove(project) }
                    }
                }
                .padding(.horizontal, 10)
            }

            Button { onAddProject() } label: {
                Label("Add project", systemImage: "plus").frame(maxWidth: .infinity)
            }
            .buttonStyle(.pill)
            .padding(.horizontal, 14)
            .padding(.top, 8)

            HStack(spacing: 8) {
                StatusDot(state: footerState)
                Text(footerText).font(.system(size: 10, design: .monospaced)).foregroundStyle(NothingTheme.inkDim).lineLimit(1)
            }
            .padding(18)
        }
        .frame(width: 216)
        .background(NothingTheme.canvas)
        .overlay(alignment: .trailing) { Rectangle().fill(NothingTheme.line).frame(width: 1) }
    }

    private struct NavItem { let tab: WorkspaceTab; let state: ServiceState; let count: Int }

    private var navItems: [NavItem] {
        [
            NavItem(tab: .runners, state: runnerState, count: runnerCount),
            NavItem(tab: .scripts, state: scriptState, count: scriptCount),
            NavItem(tab: .coverage, state: .unknown, count: 0),
            NavItem(tab: .policy, state: policyPendingCount > 0 ? .warning : .unknown, count: policyPendingCount),
            NavItem(tab: .tests, state: testAlertCount > 0 ? .warning : .unknown, count: testAlertCount),
            NavItem(tab: .settings, state: .unknown, count: 0),
        ]
    }

    var aggregateState: ServiceState {
        guard !projects.isEmpty else { return .unknown }
        let states = projects.map(stateForProject)
        if states.contains(.offline) { return .offline }
        if states.contains(.warning) { return .warning }
        if states.contains(.unknown) { return .unknown }
        return .online
    }

    var footerState: ServiceState {
        switch workspaceTab {
        case .projects:
            aggregateState
        case .runners:
            runnerState
        case .scripts:
            scriptState
        case .coverage:
            .unknown
        case .policy:
            policyPendingCount > 0 ? .warning : .unknown
        case .tests:
            testAlertCount > 0 ? .warning : .unknown
        case .settings:
            .unknown
        }
    }

    var footerText: String {
        switch workspaceTab {
        case .projects:
            projects.isEmpty ? "No projects" : aggregateState.rawValue
        case .runners:
            runnerCount == 0 ? "Runners not loaded" : "\(runnerCount) runners · \(runnerState.rawValue)"
        case .scripts:
            scriptCount == 0 ? "No scripts" : "\(scriptCount) scripts · \(scriptState.rawValue)"
        case .coverage:
            "Gate coverage"
        case .policy:
            policyPendingCount == 0 ? "No pending approvals" : "\(policyPendingCount) waiting for approval"
        case .tests:
            testAlertCount == 0 ? "No open alerts" : "\(testAlertCount) open alerts"
        case .settings:
            "Server settings"
        }
    }
}

struct WorkspaceMenuRow: View {
    let tab: WorkspaceTab
    let state: ServiceState
    let count: Int
    let isActive: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                StatusDot(state: state, onLight: isActive)
                Text(tab.title)
                    .font(.system(size: 11, design: .monospaced))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                if count > 0 {
                    Text("\(count)").nothingDisplay(15)
                }
            }
            .foregroundStyle(isActive ? Color.black : NothingTheme.ink)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(isActive ? NothingTheme.ink : Color.clear, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(tab.title)
    }
}
