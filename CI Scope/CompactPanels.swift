import SwiftUI

struct CompactRunsPanel: View {
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

struct RunRow: View {
    let run: GitHubRun

    var body: some View {
        HStack(spacing: 9) {
            StatusDot(state: state)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(run.displayTitle)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text(run.compactConclusion)
                        .font(.caption.weight(.semibold))
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
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(Color.secondary.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    var state: ServiceState {
        if run.conclusion == "success" { return .online }
        if run.status != "completed" { return .warning }
        return .offline
    }

    var color: Color {
        switch state {
        case .online: .green
        case .warning: .orange
        case .offline: .red
        case .unknown: .secondary
        }
    }

    func shortDate(_ value: String) -> String {
        value
            .replacingOccurrences(of: "T", with: " ")
            .replacingOccurrences(of: "Z", with: "")
    }
}

struct CompactLogsPanel: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        PanelShell(title: "Local Runner Logs", icon: "doc.text.magnifyingglass") {
            VStack(spacing: 8) {
                Picker("Log", selection: $viewModel.selectedLog) {
                    ForEach(LogKind.allCases) { kind in
                        Text(kind.rawValue).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                HStack(spacing: 8) {
                    Text(logTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    FileOpenButton(title: "stdout", path: viewModel.snapshot.logs.stdoutPath)
                    FileOpenButton(title: "stderr", path: viewModel.snapshot.logs.stderrPath)
                    FileOpenButton(title: "runner", path: viewModel.snapshot.logs.latestRunnerDiagPath)
                    FileOpenButton(title: "worker", path: viewModel.snapshot.logs.latestWorkerDiagPath)
                }

                LogScroll(text: logText)
            }
            .padding(10)
        }
    }

    var logText: String {
        let text = viewModel.selectedLogText()
        return text.isEmpty ? "No log output." : text
    }

    var logTitle: String {
        switch viewModel.selectedLog {
        case .stdout: "service stdout"
        case .stderr: "service stderr"
        case .runnerDiag: viewModel.snapshot.logs.latestRunnerDiagName
        case .workerDiag: viewModel.snapshot.logs.latestWorkerDiagName
        }
    }
}

struct CompactStagesPanel: View {
    let stages: [ScriptStage]

    var body: some View {
        PanelShell(title: "Local Scripts", icon: "curlybraces.square") {
            ScrollView {
                LazyVStack(spacing: 7) {
                    ForEach(stages) { stage in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(stage.title)
                                    .font(.callout.weight(.semibold))
                                    .lineLimit(1)
                                Spacer()
                                Text(stage.source)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                FileOpenButton(title: "Open Source", path: stage.sourcePath, icon: "doc.text.magnifyingglass")
                            }
                            Text(stage.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            if let command = stage.command {
                                Text(command)
                                    .font(.caption.monospaced())
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

struct CompactConsolePanel: View {
    @ObservedObject var runner: LocalCommandRunner

    var body: some View {
        PanelShell(title: "Local Command Output", icon: "terminal") {
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
