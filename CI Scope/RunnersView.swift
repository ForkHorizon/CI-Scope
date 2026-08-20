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
            .help(
                "Unified queued workflow jobs from the V2 control plane. The Agent dispatches jobs to runner instances."
            )
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
