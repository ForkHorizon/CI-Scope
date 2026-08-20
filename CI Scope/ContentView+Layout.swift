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
      .padding(14)
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
