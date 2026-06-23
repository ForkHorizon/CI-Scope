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
    let onSelect: (CIProject) -> Void
    let onRemove: (CIProject) -> Void
    let onAddProject: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Label("Menu", systemImage: "sidebar.left")
                    .font(.caption.weight(.semibold))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            VStack(spacing: 7) {
                WorkspaceMenuRow(
                    tab: .runners,
                    state: runnerState,
                    count: runnerCount,
                    isActive: workspaceTab == .runners
                ) {
                    workspaceTab = .runners
                }

                WorkspaceMenuRow(
                    tab: .scripts,
                    state: scriptState,
                    count: scriptCount,
                    isActive: workspaceTab == .scripts
                ) {
                    workspaceTab = .scripts
                }

                WorkspaceMenuRow(
                    tab: .settings,
                    state: .unknown,
                    count: 0,
                    isActive: workspaceTab == .settings
                ) {
                    workspaceTab = .settings
                }
            }
            .padding(10)

            Divider()

            ScrollView {
                LazyVStack(spacing: 8) {
                    HStack {
                        Text("Projects")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 2)

                    if projects.isEmpty {
                        EmptyState(icon: "folder.badge.plus", text: "No projects saved")
                            .frame(minHeight: 150)
                    }

                    ForEach(projects) { project in
                        ProjectMenuRow(
                            project: project,
                            state: stateForProject(project),
                            isActive: workspaceTab == .projects && project.id == selectedProjectID
                        ) {
                            onSelect(project)
                        } onRemove: {
                            onRemove(project)
                        }
                    }

                    Button {
                        onAddProject()
                    } label: {
                        Label("Add Project", systemImage: "plus")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color(nsColor: .windowBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.12))
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Add Project")
                }
                .padding(10)
            }

            Divider()

            VStack(alignment: .leading, spacing: 7) {
                Text("Projects")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    StatusDot(state: footerState)
                    Text(footerText)
                        .font(.caption2.monospacedDigit())
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
        .frame(width: 204)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.58))
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
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(stateColor.opacity(isActive ? 0.16 : 0.08))
                    Image(systemName: tab.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isActive ? stateColor : .secondary)
                }
                .frame(width: 31, height: 31)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(tab.title)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(isActive ? Color.accentColor : Color.primary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        StatusDot(state: state)
                    }
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(isActive ? Color.accentColor : .secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, minHeight: 51, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .background(isActive ? Color.accentColor.opacity(0.11) : Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isActive ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.12))
        )
        .help(tab.title)
    }

    var detail: String {
        switch tab {
        case .projects:
            count == 1 ? "1 project" : "\(count) projects"
        case .runners:
            count == 0 ? "Load runner status" : "\(count) configured"
        case .scripts:
            count == 1 ? "1 script" : "\(count) scripts"
        case .settings:
            "Server queue"
        }
    }

    var stateColor: Color {
        switch state {
        case .online: .green
        case .warning: .orange
        case .offline: .red
        case .unknown: .secondary
        }
    }
}
