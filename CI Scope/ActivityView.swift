// What the agent on this Mac is doing: the task list, newest first, live while the tab is open.
import SwiftUI

struct ActivityView: View {
    @ObservedObject var monitor: GateJobsMonitor
    @State private var feed = FreshSet<String>()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    tile("Waiting", count(["queued"]), NothingTheme.amber).nothingEntrance(0)
                    tile("Running", count(["leased", "running"]), NothingTheme.green).nothingEntrance(1)
                    tile("Passed", count(["succeeded"]), NothingTheme.ink).nothingEntrance(2)
                    tile("Failed", count(["failed"]), NothingTheme.red).nothingEntrance(3)
                }
                Text(summary).font(NothingTheme.body).foregroundStyle(NothingTheme.inkDim).nothingEntrance(4)
                ForEach(Array(monitor.jobs.enumerated()), id: \.element.id) { index, job in
                    row(job).nothingEntrance(index + 5)
                }
                if let message = monitor.message {
                    Text(message).font(NothingTheme.small).foregroundStyle(NothingTheme.amber).textSelection(.enabled)
                }
            }
            .padding(22)
            .animation(.smooth(duration: 0.35), value: monitor.jobs.map(\.id))
        }
        .onAppear { feed.seed(monitor.jobs.map(\.id)) }
        .onChange(of: monitor.jobs.map(\.id)) { _, ids in feed.update(ids) }
        .task {
            // Only while this tab is on screen: the server is ours, but there is no reason to ask when nobody looks.
            while !Task.isCancelled {
                await monitor.refresh()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func count(_ statuses: [String]) -> Int { monitor.jobs.filter { statuses.contains($0.status) }.count }

    /// A stat tile; the number lights up in its signal color only when there is something to see.
    private func tile(_ title: String, _ value: Int, _ signal: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).nothingCaption()
            DotCounter(value, color: value > 0 ? signal : NothingTheme.inkDim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .nothingTile(alarm: signal == NothingTheme.red && value > 0)
    }

    private var summary: String {
        if monitor.jobs.isEmpty { return "No tasks yet. A new pull request shows up here the moment it is queued." }
        return monitor.activeCount == 0 ? "Idle. Nothing is waiting." : "\(monitor.activeCount) in progress or waiting"
    }

    private func row(_ job: GateJob) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("\(job.repository) #\(job.pullRequest)").font(NothingTheme.body.weight(.semibold)).foregroundStyle(NothingTheme.ink)
                Spacer()
                Text(job.label).font(NothingTheme.small.weight(.semibold)).foregroundStyle(color(job))
            }
            let attempt = job.attempts > 1 ? " · attempt \(job.attempts)" : ""
            Text("\(job.headSha.prefix(7))\(attempt) · \(Date(timeIntervalSince1970: Double(job.updatedAt) / 1000).formatted(.relative(presentation: .named)))")
                .font(NothingTheme.small).foregroundStyle(NothingTheme.inkDim)
            if let summary = job.report?.summary, !summary.isEmpty {
                Text(summary).font(NothingTheme.small).foregroundStyle(NothingTheme.inkDim).textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .nothingRow(fresh: feed.fresh.contains(job.id), tint: color(job))
    }

    private func color(_ job: GateJob) -> Color {
        switch job.status {
        case "succeeded": NothingTheme.green
        case "failed": NothingTheme.red
        case "queued", "leased", "running": NothingTheme.amber
        default: NothingTheme.inkDim
        }
    }
}
