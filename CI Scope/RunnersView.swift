import SwiftUI

struct RunnersView: View {
    @ObservedObject var viewModel: RunnerFleetViewModel

    var body: some View {
        VStack(spacing: 12) {
            RunnerFleetSummary(snapshot: viewModel.snapshot, isLoading: viewModel.isLoading)

            if !viewModel.snapshot.errors.isEmpty {
                RunnerErrorStrip(errors: viewModel.snapshot.errors)
            }

            ScrollView {
                LazyVStack(spacing: 10) {
                    if viewModel.snapshot.runners.isEmpty && !viewModel.isLoading {
                        RunnerEmptyState()
                    }

                    if let runner = viewModel.snapshot.runners.first {
                        RunnerCard(runner: runner)
                    }
                }
                .padding(12)
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.13))
            )
        }
        .overlay(alignment: .topTrailing) {
            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .padding(10)
            }
        }
    }
}

private struct RunnerFleetSummary: View {
    let snapshot: RunnerFleetSnapshot
    let isLoading: Bool

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            RunnerSummaryTile(
                title: "Runner",
                value: isLoading && snapshot.runners.isEmpty ? "..." : "\(min(snapshot.runners.count, 1))",
                detail: snapshot.runners.isEmpty ? stateText : "MacBook",
                icon: "desktopcomputer",
                state: snapshot.state
            )
            RunnerSummaryTile(
                title: "Running",
                value: "\(snapshot.activeJobCount)",
                detail: "serial execution",
                icon: "play.circle",
                state: snapshot.activeJobCount > 0 ? .warning : .online
            )
            RunnerSummaryTile(
                title: "Queue",
                value: "\(snapshot.queuedJobCount)",
                detail: "shared queue",
                icon: "tray.full",
                state: snapshot.queuedJobCount > 0 ? .warning : .online
            )
            .help("Unified queued workflow jobs from all sub-runners. The broker dispatches one job at a time.")
            RunnerSummaryTile(
                title: "Sub-runners",
                value: "\(snapshot.subRunnerCount)",
                detail: "hidden settings",
                icon: "slider.horizontal.3",
                state: snapshot.subRunnerCount > 0 ? .online : .unknown
            )
        }
    }

    private var columns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10),
        ]
    }

    private var stateText: String {
        snapshot.runners.isEmpty ? "not loaded" : snapshot.state.rawValue.lowercased()
    }

}

private struct RunnerSummaryTile: View {
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

private struct RunnerCard: View {
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
                RunnerMetric(title: "Broker", value: runner.launchctlState.capitalized, detail: localDetail, state: runner.localState)
                RunnerMetric(
                    title: "Dispatcher", value: runner.remoteStatus.capitalized, detail: "one job at a time", state: runner.githubState)
                RunnerMetric(
                    title: "Running", value: "\(runner.activeJobs.count)", detail: activeSummary,
                    state: runner.activeJobs.isEmpty ? .online : .warning)
                RunnerMetric(
                    title: "Queue", value: "\(runner.queuedJobs.count)", detail: "shared jobs",
                    state: runner.queuedJobs.isEmpty ? .online : .warning
                )
                .help("Queued jobs from organization and private sub-runners. Only one job is dispatched at a time.")
            }

            RunnerWebhookStrip(webhook: runner.webhook)

            RunnerWorkSection(
                title: "Running Now", emptyText: runner.isBusy ? "Busy, job not visible yet" : "Idle", items: runner.activeJobs)
            RunnerWorkSection(title: "Queue", emptyText: "No queued jobs", items: runner.queuedJobs)

            RunnerSubRunnerDisclosure(subRunners: runner.subRunners)

            if !runner.missingLabels.isEmpty {
                RunnerWarningLine(text: "Missing labels: \(runner.missingLabels.joined(separator: ", "))")
            }

            RunnerLabelStrip(labels: runner.labels)
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
