import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = DashboardViewModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    statusGrid
                    CommandPanel(runner: viewModel.commandRunner)
                    RunsPanel(runs: viewModel.snapshot.runs)
                    HStack(alignment: .top, spacing: 16) {
                        LogsPanel(viewModel: viewModel)
                        StagesPanel(stages: viewModel.snapshot.stages)
                    }
                }
                .padding(18)
            }
        }
        .frame(minWidth: 1120, minHeight: 780)
        .task {
            viewModel.refresh()
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "waveform.path.ecg.rectangle")
                .font(.title2)
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text("CI Scope")
                    .font(.title3.weight(.semibold))
                Text(viewModel.config.repositorySlug)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if viewModel.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            }

            Text(viewModel.snapshot.refreshedAt.formatted(date: .omitted, time: .standard))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Button {
                viewModel.refresh()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: [.command])
            .disabled(viewModel.isRefreshing)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }

    private var statusGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 4), spacing: 16) {
            RunnerCard(status: viewModel.snapshot.runner)
            OllamaCard(status: viewModel.snapshot.ollama)
            NexusUnityCard(snapshot: viewModel.snapshot.nexusUnity)
            LatestRunCard(run: viewModel.snapshot.runs.first)
        }
    }
}

private struct RunnerCard: View {
    let status: RunnerStatus

    var body: some View {
        MetricCard(title: "Runner", state: status.state, systemImage: "server.rack") {
            metric("Service", status.launchctlState)
            metric("PID", pidPair)
            metric("Uptime", status.uptime)
            Text(status.lastLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var pidPair: String {
        let service = status.servicePID.map(String.init) ?? "-"
        let listener = status.listenerPID.map(String.init) ?? "-"
        return "\(service) / \(listener)"
    }
}

private struct OllamaCard: View {
    let status: OllamaStatus

    var body: some View {
        MetricCard(title: "Ollama", state: status.state, systemImage: "cpu") {
            metric("Loaded", "\(status.loadedModels.count)")
            metric("Available", "\(status.availableModels.count)")
            if let model = status.loadedModels.first {
                metric("VRAM", ByteCountFormatter.string(fromByteCount: model.sizeVRAM ?? model.size ?? 0, countStyle: .memory))
                Text(model.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(status.error ?? status.loadedSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct NexusUnityCard: View {
    let snapshot: NexusUnitySnapshot

    var body: some View {
        MetricCard(title: "Nexus Unity", state: snapshot.state, systemImage: "cube.transparent") {
            metric("State", snapshot.status?.state ?? "-")
            metric("PID", snapshot.status?.processId.map(String.init) ?? "-")
            metric("Unity", snapshot.status?.unityVersion ?? "-")
            Text(snapshot.status?.projectPath ?? snapshot.error ?? "No status.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct LatestRunCard: View {
    let run: GitHubRun?

    var body: some View {
        MetricCard(title: "Latest Run", state: runState, systemImage: "checkmark.seal") {
            metric("Result", run?.compactConclusion ?? "-")
            metric("Branch", run?.headBranch ?? "-")
            metric("Event", run?.event ?? "-")
            Text(run?.displayTitle ?? "No GitHub runs loaded.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var runState: ServiceState {
        guard let run else { return .unknown }
        if run.conclusion == "success" { return .online }
        if run.status != "completed" { return .warning }
        return .offline
    }
}

private struct CommandPanel: View {
    @ObservedObject var runner: LocalCommandRunner

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Local Commands", systemImage: "terminal")
                    .font(.headline)
                Spacer()
                if runner.isRunning {
                    ProgressView()
                        .controlSize(.small)
                    Text(runner.activeTitle ?? "Running")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button(role: .destructive) {
                        runner.stop()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                } else if let code = runner.lastExitCode {
                    Text("Exit \(code)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(code == 0 ? .green : .red)
                }
            }

            HStack(spacing: 10) {
                ForEach(LocalCommandPreset.allCases) { preset in
                    Button {
                        runner.run(preset)
                    } label: {
                        Label(preset.title, systemImage: preset.systemImage)
                            .frame(minWidth: 112)
                    }
                    .disabled(runner.isRunning)
                }
            }

            ScrollView {
                Text(runner.output.isEmpty ? "No command output." : runner.output)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(height: 170)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.18))
            )
        }
        .panelStyle()
    }
}

private struct RunsPanel: View {
    let runs: [GitHubRun]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("GitHub Runs", systemImage: "point.3.connected.trianglepath.dotted")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    header("Result")
                    header("Workflow")
                    header("Branch")
                    header("Event")
                    header("Created")
                    header("Title")
                }
                Divider()
                    .gridCellColumns(6)
                ForEach(runs.prefix(10)) { run in
                    GridRow {
                        runBadge(run.compactConclusion)
                        Text(run.workflowName)
                        Text(run.headBranch)
                        Text(run.event)
                        Text(shortDate(run.createdAt))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Link(run.displayTitle, destination: URL(string: run.url)!)
                            .lineLimit(1)
                    }
                    .font(.caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .panelStyle()
    }

    private func header(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func runBadge(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(text == "success" ? .green : .orange)
            .frame(minWidth: 68, alignment: .leading)
    }

    private func shortDate(_ value: String) -> String {
        value.replacingOccurrences(of: "T", with: " ").replacingOccurrences(of: "Z", with: "")
    }
}

private struct LogsPanel: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Runner Logs", systemImage: "doc.text.magnifyingglass")
                    .font(.headline)
                Spacer()
                Picker("Log", selection: $viewModel.selectedLog) {
                    ForEach(LogKind.allCases) { kind in
                        Text(kind.rawValue).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 430)
            }

            Text(logTitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView {
                Text(logText)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(minHeight: 330)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.18))
            )
        }
        .panelStyle()
        .frame(maxWidth: .infinity)
    }

    private var logText: String {
        let text = viewModel.selectedLogText()
        return text.isEmpty ? "No log output." : text
    }

    private var logTitle: String {
        switch viewModel.selectedLog {
        case .stdout:
            "service stdout"
        case .stderr:
            "service stderr"
        case .runnerDiag:
            viewModel.snapshot.logs.latestRunnerDiagName
        case .workerDiag:
            viewModel.snapshot.logs.latestWorkerDiagName
        }
    }
}

private struct StagesPanel: View {
    let stages: [ScriptStage]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Scripts Registry", systemImage: "curlybraces.square")
                .font(.headline)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(stages) { stage in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(stage.title)
                                    .font(.caption.weight(.semibold))
                                Spacer()
                                Text(stage.source)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            Text(stage.detail)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            if let command = stage.command {
                                Text(command)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .padding(8)
                        .background(Color.secondary.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
            .frame(minHeight: 330)
        }
        .panelStyle()
        .frame(width: 360)
    }
}

private struct MetricCard<Content: View>: View {
    let title: String
    let state: ServiceState
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.headline)
                Spacer()
                StatusBadge(state: state)
            }
            content
            Spacer(minLength: 0)
        }
        .panelStyle()
        .frame(minHeight: 168)
    }
}

private struct StatusBadge: View {
    let state: ServiceState

    var body: some View {
        Text(state.rawValue)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
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

@ViewBuilder
private func metric(_ title: String, _ value: String) -> some View {
    HStack {
        Text(title)
            .foregroundStyle(.secondary)
        Spacer()
        Text(value)
            .font(.caption.monospacedDigit())
            .lineLimit(1)
    }
    .font(.caption)
}

private extension View {
    func panelStyle() -> some View {
        self
            .padding(14)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.14))
            )
    }
}

#Preview {
    ContentView()
}
