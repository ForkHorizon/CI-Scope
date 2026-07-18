import SwiftUI

@MainActor
extension ContentView {
    var dashboardSurface: some View {
        VStack(spacing: 0) {
            header
            Divider()
            dashboardContent
        }
        .frame(minWidth: 587, maxWidth: .infinity)
    }

    @ViewBuilder
    var dashboardContent: some View {
        switch workspaceTab {
        case .projects:
            projectDashboardContent
        case .runners:
            RunnersView(viewModel: runnerFleetViewModel)
                .padding(14)
        case .scripts:
            ScriptsView(
                store: scriptStore,
                installer: scriptInstallViewModel,
                projects: projectStore.projects,
                selectedProject: selectedProject,
                onInstallSuccess: { project in
                    Task {
                        await projectCIViewModel.load(project)
                    }
                }
            )
        case .coverage:
            GateMatrixView(
                projects: projectStore.projects,
                gateScripts: gateScripts,
                installViewModel: scriptInstallViewModel,
                onInstalled: { project in
                    Task {
                        await projectCIViewModel.load(project)
                    }
                }
            )
            .padding(14)
        case .settings:
            SettingsView(store: settingsStore)
        }
    }

    /// The managed gates in canonical order, for the coverage matrix columns.
    var gateScripts: [AutomationScript] {
        AutomationScriptSeedProvider.defaultSeedIDs.compactMap { id in
            scriptStore.scripts.first { $0.defaultSeedID == id }
        }
    }

    @ViewBuilder
    var projectDashboardContent: some View {
        if let selectedProject {
            VStack(spacing: 12) {
                ProjectCIPanel(
                    project: selectedProject,
                    snapshot: projectCIViewModel.snapshot(for: selectedProject.id),
                    isLoading: projectCIViewModel.loadingProjectID == selectedProject.id,
                    scripts: scriptStore.scripts,
                    isBrokerManaged: isBrokerManaged(selectedProject),
                    removalSnapshot: { script in
                        scriptInstallViewModel.removalSnapshot(for: script, project: selectedProject)
                    },
                    onAttachToBroker: {
                        attachToBroker(selectedProject)
                    },
                    onRemoveScript: { script in
                        scriptInstallViewModel.remove(script: script, project: selectedProject) {
                            refreshSelectedProject()
                        }
                    },
                    installViewModel: scriptInstallViewModel
                )
                .frame(minHeight: 260, maxHeight: .infinity)
            }
            .padding(14)
        } else {
            EmptyProjectDashboard {
                isAddingProject = true
            }
            .padding(14)
        }
    }

    var header: some View {
        HStack(spacing: 10) {
            Button {
                isProjectMenuOpen.toggle()
            } label: {
                Image(systemName: "sidebar.leading")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isProjectMenuOpen ? Color.accentColor : Color.primary)
                    .frame(width: 28, height: 28)
                    .background(isProjectMenuOpen ? Color.accentColor.opacity(0.13) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help(isProjectMenuOpen ? "Hide projects" : "Show projects")
            .keyboardShortcut("b", modifiers: [.command])

            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.accentColor.opacity(0.16))
                Image(systemName: headerIcon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 1) {
                Text(headerTitle)
                    .font(.system(size: 16, weight: .semibold))
                Text(headerSubtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            StatusDot(state: headerState)
            if let refreshedAt {
                Text(refreshedAt.formatted(date: .omitted, time: .standard))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Button {
                refreshCurrentTab()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(!canRefresh || isRefreshing)
            .overlay {
                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .help("Refresh")
            .keyboardShortcut("r", modifiers: [.command])
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.thinMaterial)
    }
}
