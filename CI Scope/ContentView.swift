import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = DashboardViewModel()
    @StateObject private var projectStore = ProjectStore()
    @StateObject private var projectCIViewModel = ProjectCIViewModel()
    @State private var section: DashboardSection = .runs
    @State private var isProjectMenuOpen = true
    @State private var isAddingProject = false

    var body: some View {
        HStack(spacing: 0) {
            if isProjectMenuOpen {
                ProjectMenuPanel(
                    projects: projectStore.projects,
                    selectedProjectID: projectStore.selectedProjectID,
                    stateForProject: state(for:),
                    onSelect: selectProject,
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
        .task {
            viewModel.refresh()
        }
        .task(id: selectedProject.id) {
            if !selectedProject.isPrimary {
                await projectCIViewModel.load(selectedProject)
            }
        }
        .sheet(isPresented: $isAddingProject) {
            AddProjectSheet { input in
                try projectStore.addProject(from: input)
            }
        }
    }

    private var dashboardSurface: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if selectedProject.isPrimary {
                VStack(spacing: 12) {
                    statusGrid
                    CommandStrip(runner: viewModel.commandRunner)
                    sectionPicker
                    contentPanel
                }
                .padding(14)
            } else {
                ProjectCIPanel(
                    project: selectedProject,
                    snapshot: projectCIViewModel.snapshot(for: selectedProject.id),
                    isLoading: projectCIViewModel.loadingProjectID == selectedProject.id
                )
                    .padding(14)
            }
        }
        .frame(minWidth: 587, maxWidth: .infinity)
    }

    private var header: some View {
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
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 1) {
                Text("CI Scope")
                    .font(.system(size: 16, weight: .semibold))
                Text(selectedProject.repositorySlug)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            StatusDot(state: state(for: selectedProject))
            Text(refreshedAt.formatted(date: .omitted, time: .standard))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Button {
                refreshSelectedProject()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(isRefreshing)
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

    private var statusGrid: some View {
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
                title: "Unity",
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

    private var sectionPicker: some View {
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
    private var contentPanel: some View {
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

    private var runnerDetail: String {
        let pid = viewModel.snapshot.runner.listenerPID ?? viewModel.snapshot.runner.servicePID
        return "PID \(pid.map(String.init) ?? "-") · \(viewModel.snapshot.runner.uptime)"
    }

    private var ollamaDetail: String {
        guard let model = viewModel.snapshot.ollama.loadedModels.first else {
            return "\(viewModel.snapshot.ollama.availableModels.count) models"
        }

        let bytes = model.sizeVRAM ?? model.size ?? 0
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .memory)
    }

    private var unityDetail: String {
        let pid = viewModel.snapshot.nexusUnity.status?.processId.map(String.init) ?? "-"
        let version = viewModel.snapshot.nexusUnity.status?.unityVersion ?? "-"
        return "PID \(pid) · \(version)"
    }

    private var latestRunState: ServiceState {
        guard let run = viewModel.snapshot.runs.first else { return .unknown }
        if run.conclusion == "success" { return .online }
        if run.status != "completed" { return .warning }
        return .offline
    }

    private var selectedProject: CIProject {
        projectStore.selectedProject
    }

    private var isRefreshing: Bool {
        selectedProject.isPrimary
            ? viewModel.isRefreshing
            : projectCIViewModel.loadingProjectID == selectedProject.id
    }

    private var refreshedAt: Date {
        if selectedProject.isPrimary {
            return viewModel.snapshot.refreshedAt
        }
        return projectCIViewModel.snapshot(for: selectedProject.id)?.refreshedAt ?? Date()
    }

    private var projectState: ServiceState {
        let states = [
            viewModel.snapshot.runner.state,
            viewModel.snapshot.ollama.state,
            viewModel.snapshot.nexusUnity.state,
            latestRunState
        ]

        if states.contains(.offline) { return .offline }
        if states.contains(.warning) { return .warning }
        if states.allSatisfy({ $0 == .online }) { return .online }
        return .unknown
    }

    private func state(for project: CIProject) -> ServiceState {
        project.isPrimary ? projectState : projectCIViewModel.snapshot(for: project.id)?.state ?? .unknown
    }

    private func selectProject(_ project: CIProject) {
        projectStore.select(project)
        if project.isPrimary {
            viewModel.refresh()
        }
    }

    private func refreshSelectedProject() {
        if selectedProject.isPrimary {
            viewModel.refresh()
        } else {
            Task {
                await projectCIViewModel.load(selectedProject)
            }
        }
    }
}

private enum DashboardSection: String, CaseIterable, Identifiable {
    case runs
    case logs
    case scripts
    case console

    var id: String { rawValue }

    var title: String {
        switch self {
        case .runs: "Runs"
        case .logs: "Logs"
        case .scripts: "Scripts"
        case .console: "Console"
        }
    }

    var icon: String {
        switch self {
        case .runs: "point.3.connected.trianglepath.dotted"
        case .logs: "doc.text.magnifyingglass"
        case .scripts: "curlybraces.square"
        case .console: "terminal"
        }
    }
}

private struct ProjectMenuPanel: View {
    let projects: [CIProject]
    let selectedProjectID: CIProject.ID
    let stateForProject: (CIProject) -> ServiceState
    let onSelect: (CIProject) -> Void
    let onAddProject: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Label("Projects", systemImage: "square.grid.2x2")
                    .font(.caption.weight(.semibold))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(projects) { project in
                        ProjectMenuRow(
                            project: project,
                            state: stateForProject(project),
                            isActive: project.id == selectedProjectID
                        ) {
                            onSelect(project)
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
                Text("Local")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    StatusDot(state: aggregateState)
                    Text(aggregateState.rawValue)
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

    private var aggregateState: ServiceState {
        let states = projects.map(stateForProject)
        if states.contains(.offline) { return .offline }
        if states.contains(.warning) { return .warning }
        if states.contains(.unknown) { return .unknown }
        return .online
    }
}

private struct ProjectMenuRow: View {
    let project: CIProject
    let state: ServiceState
    let isActive: Bool
    let onSelect: () -> Void

    var body: some View {
        Button {
            onSelect()
        } label: {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(stateColor.opacity(isActive ? 0.15 : 0.08))
                    Image(systemName: project.isPrimary ? "cube.transparent" : "folder")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isActive ? stateColor : .secondary)
                }
                .frame(width: 31, height: 31)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(project.title)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        StatusDot(state: state)
                    }

                    Text(project.repositorySlug)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(badge)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(isActive ? Color.accentColor : .secondary)
                        .lineLimit(1)
                }
            }
            .padding(9)
            .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .frame(height: 66)
        .background(isActive ? Color.accentColor.opacity(0.11) : Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isActive ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.12))
        )
    }

    private var badge: String {
        if isActive { return "Active" }
        return project.isPrimary ? "Primary" : "Saved"
    }

    private var stateColor: Color {
        switch state {
        case .online: .green
        case .warning: .orange
        case .offline: .red
        case .unknown: .secondary
        }
    }
}

private struct ProjectCIPanel: View {
    let project: CIProject
    let snapshot: ProjectCISnapshot?
    let isLoading: Bool

    var body: some View {
        PanelShell(title: "GitHub CI", icon: "point.3.connected.trianglepath.dotted") {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 7)
                                .fill(Color.accentColor.opacity(0.14))
                            Image(systemName: "folder.badge.gearshape")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                        .frame(width: 36, height: 36)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(project.title)
                                .font(.system(size: 16, weight: .semibold))
                                .lineLimit(1)
                            Text(project.repositorySlug)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        Spacer()

                        if isLoading {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            StatusDot(state: snapshot?.state ?? .unknown)
                        }
                    }

                    LazyVGrid(columns: projectInfoColumns, spacing: 8) {
                        LimitedStatusRow(title: "Repository", value: project.remoteURL, icon: "link", state: .online)
                        LimitedStatusRow(title: "GitHub CLI", value: githubAuthSummary, icon: "person.crop.circle.badge.checkmark", state: snapshot?.auth.state ?? .unknown)
                        LimitedStatusRow(title: "GitHub Actions", value: ciSummary, icon: "checkmark.seal", state: snapshot?.state ?? .unknown)
                        LimitedStatusRow(title: "Local runner", value: "Not configured", icon: "server.rack", state: .unknown)
                    }

                    if let error = snapshot?.error {
                        ErrorBox(text: error)
                    }

                    if let snapshot, !snapshot.workflows.isEmpty {
                        ProjectWorkflowList(workflows: snapshot.workflows)
                    }

                    if let snapshot, !snapshot.runs.isEmpty {
                        ProjectRunList(runs: snapshot.runs)
                    }

                    if snapshot?.error == nil, snapshot?.workflows.isEmpty != false, snapshot?.runs.isEmpty != false, !isLoading {
                        EmptyState(icon: "icloud.slash", text: "No actions available")
                    }
                }
                .padding(12)
            }
        }
    }

    private var ciSummary: String {
        guard let snapshot else {
            return isLoading ? "Loading" : "Not loaded"
        }
        if let error = snapshot.error, !error.isEmpty {
            if snapshot.workflows.isEmpty && snapshot.runs.isEmpty {
                return "Error"
            }
            let runs = snapshot.runs.isEmpty ? "runs unavailable" : "\(snapshot.runs.count) runs"
            return "\(snapshot.workflows.count) workflows · \(runs)"
        }
        if snapshot.workflows.isEmpty && snapshot.runs.isEmpty {
            return "No actions available"
        }
        return "\(snapshot.workflows.count) workflows · \(snapshot.runs.count) runs"
    }

    private var githubAuthSummary: String {
        guard let auth = snapshot?.auth else {
            return isLoading ? "Checking" : "Not checked"
        }
        return auth.summary
    }

    private var projectInfoColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8)
        ]
    }
}

private struct ProjectWorkflowList: View {
    let workflows: [GitHubWorkflow]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Workflows")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(workflows) { workflow in
                HStack(spacing: 8) {
                    StatusDot(state: workflow.state.lowercased().contains("disabled") ? .warning : .online)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(workflow.name)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Text(workflow.path ?? workflow.state)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Text(workflow.state)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .background(Color.secondary.opacity(0.055))
                .clipShape(RoundedRectangle(cornerRadius: 7))
            }
        }
    }
}

private struct ProjectRunList: View {
    let runs: [GitHubRun]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Recent Runs")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(runs.prefix(8)) { run in
                Link(destination: URL(string: run.url)!) {
                    RunRow(run: run)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct ErrorBox: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.monospaced())
            .foregroundStyle(.red)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(9)
            .background(Color.red.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.red.opacity(0.18))
            )
        }
}

private struct LimitedStatusRow: View {
    let title: String
    let value: String
    let icon: String
    let state: ServiceState

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(value)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()
            StatusDot(state: state)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(Color.secondary.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

private struct AddProjectSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var errorMessage: String?

    let onAdd: (String) throws -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Add Project", systemImage: "plus")
                    .font(.headline)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Git repository URL")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("git@github.com:owner/repo.git", text: $input)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(submit)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Add Project") {
                    submit()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 420)
    }

    private func submit() {
        do {
            try onAdd(input)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct StatusTile: View {
    let title: String
    let value: String
    let detail: String
    let icon: String
    let state: ServiceState

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(stateColor.opacity(0.12))
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(stateColor)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                    StatusDot(state: state)
                }
                Text(value)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(height: 70)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.13))
        )
    }

    private var stateColor: Color {
        switch state {
        case .online: .green
        case .warning: .orange
        case .offline: .red
        case .unknown: .secondary
        }
    }
}

private struct CommandStrip: View {
    @ObservedObject var runner: LocalCommandRunner

    var body: some View {
        VStack(spacing: 9) {
            HStack {
                Label("Commands", systemImage: "bolt.horizontal")
                    .font(.caption.weight(.semibold))
                Spacer()
                if runner.isRunning {
                    ProgressView()
                        .controlSize(.small)
                    Text(runner.activeTitle ?? "Running")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Button(role: .destructive) {
                        runner.stop()
                    } label: {
                        Image(systemName: "stop.fill")
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .help("Stop")
                } else if let code = runner.lastExitCode {
                    Text("Exit \(code)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(code == 0 ? .green : .red)
                }
            }

            HStack(spacing: 7) {
                ForEach(LocalCommandPreset.allCases) { preset in
                    CommandButton(preset: preset, runner: runner)
                }
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.13))
        )
    }
}

private struct CommandButton: View {
    let preset: LocalCommandPreset
    @ObservedObject var runner: LocalCommandRunner

    var body: some View {
        Button {
            runner.run(preset)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: preset.systemImage)
                    .font(.system(size: 14, weight: .semibold))
                Text(preset.title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 45)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.secondary.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
        .disabled(runner.isRunning)
        .opacity(runner.isRunning ? 0.48 : 1)
        .help(preset.title)
    }
}

private struct CompactRunsPanel: View {
    let runs: [GitHubRun]

    var body: some View {
        PanelShell(title: "GitHub Runs", icon: "point.3.connected.trianglepath.dotted") {
            ScrollView {
                LazyVStack(spacing: 7) {
                    ForEach(runs.prefix(12)) { run in
                        Link(destination: URL(string: run.url)!) {
                            RunRow(run: run)
                        }
                        .buttonStyle(.plain)
                    }
                    if runs.isEmpty {
                        EmptyState(icon: "icloud.slash", text: "No runs loaded")
                    }
                }
                .padding(10)
            }
        }
    }
}

private struct RunRow: View {
    let run: GitHubRun

    var body: some View {
        HStack(spacing: 9) {
            StatusDot(state: state)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(run.displayTitle)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text(run.compactConclusion)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(color)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    Text(run.workflowName)
                    Text("·")
                    Text(run.headBranch)
                    Text("·")
                    Text(shortDate(run.createdAt))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(Color.secondary.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private var state: ServiceState {
        if run.conclusion == "success" { return .online }
        if run.status != "completed" { return .warning }
        return .offline
    }

    private var color: Color {
        switch state {
        case .online: .green
        case .warning: .orange
        case .offline: .red
        case .unknown: .secondary
        }
    }

    private func shortDate(_ value: String) -> String {
        value
            .replacingOccurrences(of: "T", with: " ")
            .replacingOccurrences(of: "Z", with: "")
    }
}

private struct CompactLogsPanel: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        PanelShell(title: "Runner Logs", icon: "doc.text.magnifyingglass") {
            VStack(spacing: 8) {
                Picker("Log", selection: $viewModel.selectedLog) {
                    ForEach(LogKind.allCases) { kind in
                        Text(kind.rawValue).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text(logTitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                LogScroll(text: logText)
            }
            .padding(10)
        }
    }

    private var logText: String {
        let text = viewModel.selectedLogText()
        return text.isEmpty ? "No log output." : text
    }

    private var logTitle: String {
        switch viewModel.selectedLog {
        case .stdout: "service stdout"
        case .stderr: "service stderr"
        case .runnerDiag: viewModel.snapshot.logs.latestRunnerDiagName
        case .workerDiag: viewModel.snapshot.logs.latestWorkerDiagName
        }
    }
}

private struct CompactStagesPanel: View {
    let stages: [ScriptStage]

    var body: some View {
        PanelShell(title: "Scripts Registry", icon: "curlybraces.square") {
            ScrollView {
                LazyVStack(spacing: 7) {
                    ForEach(stages) { stage in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(stage.title)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                Spacer()
                                Text(stage.source)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Text(stage.detail)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            if let command = stage.command {
                                Text(command)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        .padding(9)
                        .background(Color.secondary.opacity(0.055))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                    if stages.isEmpty {
                        EmptyState(icon: "curlybraces.square", text: "No stages parsed")
                    }
                }
                .padding(10)
            }
        }
    }
}

private struct CompactConsolePanel: View {
    @ObservedObject var runner: LocalCommandRunner

    var body: some View {
        PanelShell(title: "Command Output", icon: "terminal") {
            VStack(spacing: 8) {
                HStack {
                    if runner.isRunning {
                        ProgressView()
                            .controlSize(.small)
                        Text(runner.activeTitle ?? "Running")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let code = runner.lastExitCode {
                        Text("Process exited with code \(code)")
                            .font(.caption)
                            .foregroundStyle(code == 0 ? .green : .red)
                    } else {
                        Text("Ready")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                LogScroll(text: runner.output.isEmpty ? "No command output." : runner.output)
            }
            .padding(10)
        }
    }
}

private struct PanelShell<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.caption.weight(.semibold))
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.055))
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.13))
        )
    }
}

private struct LogScroll: View {
    let text: String

    var body: some View {
        ScrollView {
            Text(text)
                .font(.system(size: 10, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(9)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.12))
        )
    }
}

private struct EmptyState: View {
    let icon: String
    let text: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }
}

private struct StatusDot: View {
    let state: ServiceState

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .overlay {
                Circle()
                    .stroke(color.opacity(0.35), lineWidth: 3)
            }
            .help(state.rawValue)
    }

    private var color: Color {
        switch state {
        case .online: .green
        case .warning: .orange
        case .offline: .red
        case .unknown: .secondary
        }
    }
}

#Preview {
    ContentView()
}
