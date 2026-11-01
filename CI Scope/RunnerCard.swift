import SwiftUI

struct RunnerSummaryTile: View {
    let title: String
    let value: String
    let detail: String
    let state: ServiceState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).nothingCaption().lineLimit(1)
            Text(value)
                .nothingDisplay(34)
                .foregroundStyle(color(for: state))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(detail)
                .font(NothingTheme.tiny)
                .foregroundStyle(NothingTheme.inkDim)
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nothingCard()
    }
}

struct RunnerCard: View {
    let runner: RunnerMonitorSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                RunnerIcon(icon: "desktopcomputer", state: runner.state)
                    .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 7) {
                        Text(runner.title)
                            .font(NothingTheme.body.weight(.semibold))
                            .lineLimit(1)
                        RunnerStatePill(state: runner.state, text: runnerStateText)
                    }
                    Text(runner.scope)
                        .font(NothingTheme.small)
                        .foregroundStyle(NothingTheme.inkDim)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(runner.remoteName)
                        .font(NothingTheme.small.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(runner.registeredTo)
                        .font(NothingTheme.tiny)
                        .foregroundStyle(NothingTheme.inkDim)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            LazyVGrid(columns: columns, spacing: 8) {
                RunnerMetric(
                    title: "Agent", value: runner.launchctlState.capitalized, detail: localDetail,
                    state: runner.localState)
                RunnerMetric(
                    title: "Control Plane", value: runner.remoteStatus.capitalized, detail: "VPS connected",
                    state: runner.githubState)
                RunnerMetric(
                    title: "Running", value: "\(runner.activeJobs.count)", detail: activeSummary,
                    state: runner.activeJobs.isEmpty ? .online : .warning)
                RunnerMetric(
                    title: "Queue", value: "\(runner.queuedJobs.count)", detail: "shared jobs",
                    state: runner.queuedJobs.isEmpty ? .online : .warning
                )
                .help("Queued jobs from the V2 control plane.")
            }

            VStack(alignment: .leading, spacing: 7) {
                Label("Running now", systemImage: "waveform.path.ecg")
                    .font(NothingTheme.body.weight(.semibold))
                    .foregroundStyle(NothingTheme.green)

                if runner.activeJobs.isEmpty {
                    if runner.isBusy {
                        RunnerBusyWorkCard()
                    } else {
                        RunnerWorkEmptyRow(text: "Idle")
                    }
                } else {
                    ForEach(runner.activeJobs) { item in
                        LiveWorkCard(item: item)
                    }
                }
            }

            RunnerQueueTimeline(title: "Up next", emptyText: "No queued jobs", items: runner.queuedJobs)

            DisclosureGroup("Runner health") {
                VStack(alignment: .leading, spacing: 10) {
                    RunnerWebhookStrip(webhook: runner.webhook)
                    RunnerSubRunnerDisclosure(subRunners: runner.subRunners)

                    if !runner.missingLabels.isEmpty {
                        RunnerWarningLine(
                            text: "Missing labels: \(runner.missingLabels.joined(separator: ", "))")
                    }

                    RunnerLabelStrip(labels: runner.labels)
                }
                .padding(.top, 8)
            }
            .font(NothingTheme.small.weight(.semibold))
            .foregroundStyle(NothingTheme.inkDim)
        }
        .padding(16)
        .nothingCard(radius: 18)
    }

    private var columns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8),
        ]
    }

    private var localDetail: String {
        "PID \(runner.pid.map(String.init) ?? "-") · \(runner.uptime)"
    }

    private var activeSummary: String {
        runner.activeJobs.isEmpty ? "idle" : "active jobs"
    }

    private var runnerStateText: String {
        if !runner.activeJobs.isEmpty || runner.isBusy { return "Running" }
        if runner.state == .online { return "Idle" }
        return runner.state.rawValue
    }

}
