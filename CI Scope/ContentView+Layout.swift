import SwiftUI

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
        case .localTools:
            localToolsDashboardContent
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
                    }
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

    var localToolsDashboardContent: some View {
        VStack(spacing: 12) {
            LocalToolsHeader()
            statusGrid
            CommandStrip(runner: viewModel.commandRunner)
            sectionPicker
            contentPanel
        }
        .padding(14)
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

    var statusGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ], spacing: 10) {
            StatusTile(
                title: "Runner",
                value: viewModel.snapshot.runner.launchctlState.capitalized,
                detail: runnerDetail,
                icon: "server.rack",
                state: viewModel.snapshot.runner.state
            )
            StatusTile(
                title: "Ollama",
                value: viewModel.snapshot.ollama.loadedModels.first?.name ?? "Idle",
                detail: ollamaDetail,
                icon: "cpu",
                state: viewModel.snapshot.ollama.state
            )
            StatusTile(
                title: "Unity Server",
                value: viewModel.snapshot.nexusUnity.status?.state ?? "Unknown",
                detail: unityDetail,
                icon: "cube.transparent",
                state: viewModel.snapshot.nexusUnity.state
            )
            StatusTile(
                title: "GitHub",
                value: viewModel.snapshot.runs.first?.compactConclusion.capitalized ?? "No runs",
                detail: viewModel.snapshot.runs.first?.headBranch ?? "Refresh to load",
                icon: "checkmark.seal",
                state: latestRunState
            )
        }
    }

    var sectionPicker: some View {
        HStack(spacing: 6) {
            ForEach(DashboardSection.allCases) { item in
                Button {
                    section = item
                } label: {
                    Label(item.title, systemImage: item.icon)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(section == item ? Color.accentColor.opacity(0.16) : Color.clear)
                        .foregroundStyle(section == item ? Color.accentColor : Color.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.14))
        )
    }

    @ViewBuilder
    var contentPanel: some View {
        switch section {
        case .runs:
            CompactRunsPanel(runs: viewModel.snapshot.runs)
        case .logs:
            CompactLogsPanel(viewModel: viewModel)
        case .scripts:
            CompactStagesPanel(stages: viewModel.snapshot.stages)
        case .console:
            CompactConsolePanel(runner: viewModel.commandRunner)
        }
    }
}
