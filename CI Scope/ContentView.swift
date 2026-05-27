import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = DashboardViewModel()
    @State private var section: DashboardSection = .runs

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            VStack(spacing: 12) {
                statusGrid
                CommandStrip(runner: viewModel.commandRunner)
                sectionPicker
                contentPanel
            }
            .padding(14)
        }
        .frame(minWidth: 587, idealWidth: 587, minHeight: 624, idealHeight: 624)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            viewModel.refresh()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
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
                Text(viewModel.config.repositorySlug)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            StatusDot(state: viewModel.snapshot.runner.state)
            Text(viewModel.snapshot.refreshedAt.formatted(date: .omitted, time: .standard))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Button {
                viewModel.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isRefreshing)
            .overlay {
                if viewModel.isRefreshing {
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
