import SwiftUI

@MainActor
extension ContentView {
    var dashboardSurface: some View {
        VStack(spacing: 0) {
            header
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
                        await projectCIViewModel.load(project, forceRefresh: true)
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
                        await projectCIViewModel.load(project, forceRefresh: true)
                    }
                }
            )

        case .policy:
            PolicyAdminView(admin: policyAdmin, checks: policyChecks, projects: projectStore.projects)
        case .tests:
            TestProtectionView(model: testProtection, projects: projectStore.projects)
        case .settings:
            SettingsView(store: settingsStore, v2Control: settingsStore.v2Control)
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
                    liveJobs: liveJobs(for: selectedProject),
                    scripts: scriptStore.scripts,
                    isV2Managed: isV2Managed(selectedProject),
                    v2Control: settingsStore.v2Control,
                    removalSnapshot: { script in
                        scriptInstallViewModel.removalSnapshot(for: script, project: selectedProject)
                    },
                    onAttachToRunner: {
                        attachToRunner(selectedProject)
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

    func liveJobs(for project: CIProject) -> [RunnerWorkItem] {
        var items = runnerFleetViewModel.snapshot.runners
            .flatMap(\.activeJobs)
            .filter { $0.repositorySlug.caseInsensitiveCompare(project.repositorySlug) == .orderedSame }

        let localActiveIDs = Set(items.map(\.id))
        if let runs = projectCIViewModel.snapshot(for: project.id)?.runs {
            for run in runs where run.status == "in_progress" || run.status == "queued" {
                let idStr = String(run.databaseId)
                if !localActiveIDs.contains(idStr) {
                    items.append(
                        RunnerWorkItem(
                            id: idStr,
                            repositorySlug: project.repositorySlug,
                            workflowName: run.workflowName,
                            title: run.displayTitle,
                            jobName: run.workflowName,
                            headBranch: run.headBranch,
                            status: run.status,
                            url: run.url,
                            assemblerTitle: nil,
                            assemblerScope: nil,
                            progress: nil
                        )
                    )
                }
            }
        }
        return items
    }

    var header: some View {
        HStack(spacing: 14) {
            Button {
                isProjectMenuOpen.toggle()
            } label: {
                Image(systemName: "sidebar.leading")
                    .font(.system(size: 13))
                    .foregroundStyle(isProjectMenuOpen ? NothingTheme.ink : NothingTheme.inkDim)
                    .frame(width: 30, height: 30)
                    .overlay(Circle().stroke(NothingTheme.lineStrong, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help(isProjectMenuOpen ? "Hide projects" : "Show projects")
            .keyboardShortcut("b", modifiers: [.command])

            VStack(alignment: .leading, spacing: 3) {
                Text(headerTitle)
                    .nothingDisplay(26)
                    .foregroundStyle(NothingTheme.ink)
                    .lineLimit(1)
                Text(headerSubtitle).nothingCaption().lineLimit(1)
            }

            Spacer(minLength: 8)

            StatusDot(state: headerState)
            if let refreshedAt {
                Text(refreshedAt.formatted(date: .omitted, time: .standard))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(NothingTheme.inkDim)
            }

            Button {
                refreshCurrentTab()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
                    .frame(width: 30, height: 30)
                    .overlay(Circle().stroke(NothingTheme.lineStrong, lineWidth: 1))
                    .overlay { if isRefreshing { ProgressView().controlSize(.small) } }
            }
            .buttonStyle(.plain)
            .disabled(!canRefresh || isRefreshing)
            .help("Refresh")
            .keyboardShortcut("r", modifiers: [.command])
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { Rectangle().fill(NothingTheme.line).frame(height: 1) }
    }
}
