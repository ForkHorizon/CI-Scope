// What the agent on this Mac is doing: the task list, newest first, live while the tab is open.
import SwiftUI

struct ActivityView: View {
    @ObservedObject var monitor: GateJobsMonitor

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    tile("Waiting", count(["queued"]), NothingTheme.amber)
                    tile("Running", count(["leased", "running"]), NothingTheme.green)
                    tile("Passed", count(["succeeded"]), NothingTheme.ink)
                    tile("Failed", count(["failed"]), NothingTheme.red)
                }
                Text(summary).font(NothingTheme.body).foregroundStyle(NothingTheme.inkDim)
                ForEach(monitor.jobs) { job in row(job) }
                if let message = monitor.message {
                    Text(message).font(NothingTheme.small).foregroundStyle(NothingTheme.amber).textSelection(.enabled)
                }
            }
            .padding(22)
        }
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
            Text("\(value)").nothingDisplay(34).foregroundStyle(value > 0 ? signal : NothingTheme.inkDim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(NothingTheme.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(NothingTheme.line, lineWidth: 1))
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
        .nothingRow()
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
