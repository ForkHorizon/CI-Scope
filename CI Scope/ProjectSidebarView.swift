// The left panel: alerts and settings, then the projects, then adding one.
import SwiftUI

struct ProjectMenuPanel: View {
    @Binding var workspaceTab: WorkspaceTab

    let projects: [CIProject]
    let selectedProjectID: CIProject.ID?
    let alertCount: Int
    let activeTaskCount: Int
    let stateForProject: (CIProject) -> ServiceState
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
                navRow(.activity, state: activeTaskCount > 0 ? .warning : .unknown, count: activeTaskCount)
                navRow(.alerts, state: alertCount > 0 ? .warning : .unknown, count: alertCount)
                navRow(.settings, state: .unknown, count: 0)
            }
            .padding(.horizontal, 10)

            Text("Projects").nothingCaption().padding(.horizontal, 18).padding(.top, 22).padding(.bottom, 6)

            ScrollView {
                LazyVStack(spacing: 2) {
                    if projects.isEmpty {
                        Text("No projects saved").font(NothingTheme.small).foregroundStyle(NothingTheme.inkDim).padding(8)
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
                }
                .padding(.horizontal, 10)
            }

            Button(action: onAddProject) {
                Label("Add project", systemImage: "plus").frame(maxWidth: .infinity)
            }
            .buttonStyle(.pill)
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
        }
        .frame(width: 216)
        .background(NothingTheme.canvas)
        .overlay(alignment: .trailing) { Rectangle().fill(NothingTheme.line).frame(width: 1) }
    }

    private func navRow(_ tab: WorkspaceTab, state: ServiceState, count: Int) -> some View {
        WorkspaceMenuRow(tab: tab, state: state, count: count, isActive: workspaceTab == tab) { workspaceTab = tab }
    }
}

struct WorkspaceMenuRow: View {
    let tab: WorkspaceTab
    let state: ServiceState
    let count: Int
    let isActive: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                StatusDot(state: state, onLight: isActive)
                Text(tab.title).font(.system(size: 12, weight: .medium, design: .monospaced)).textCase(.uppercase).tracking(1)
                Spacer(minLength: 0)
                if count > 0 { Text("\(count)").font(.system(size: 12, design: .monospaced)) }
            }
            .foregroundStyle(isActive ? Color.black : NothingTheme.ink)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(isActive ? NothingTheme.ink : (hovering ? NothingTheme.panel : Color.clear), in: Capsule())
            .overlay(Capsule().stroke(hovering && !isActive ? NothingTheme.line : .clear, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .pointerStyle(.link)
        .animation(.smooth(duration: 0.18), value: hovering)
        .animation(.smooth(duration: 0.25), value: isActive)
    }
}
