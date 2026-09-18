import SwiftUI

struct RunnerSummaryTile: View {
    let title: String
    let value: String
    let detail: String
    let icon: String
    let state: ServiceState

    var body: some View {
        HStack(spacing: 9) {
            RunnerIcon(icon: icon, state: state)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(value)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(height: 72)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.13))
        )
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
                            .font(.headline)
                            .lineLimit(1)
                        RunnerStatePill(state: runner.state, text: runnerStateText)
                    }
                    Text(runner.scope)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(runner.remoteName)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(runner.registeredTo)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
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
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color.accentColor)

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
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(runnerColor.opacity(0.2))
        )
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

    private var runnerColor: Color {
        color(for: runner.state)
    }
}
