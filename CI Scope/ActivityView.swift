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
                    let arrived = feed.fresh.contains(job.id)
                    row(job)
                        .nothingEntrance(index + 5, enabled: !arrived)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if let message = monitor.message {
                    Text(message).font(NothingTheme.small).foregroundStyle(NothingTheme.amber).textSelection(.enabled)
                }
            }
            .padding(22)
            .animation(.smooth(duration: 0.35), value: monitor.jobs.map(\.id))
        }
        .onAppear { if monitor.lastUpdated != nil { feed.seed(monitor.jobs.map(\.id)) } }
        .onChange(of: monitor.jobs.map(\.id)) { _, ids in feed.update(ids) }
        // The first answer only records what is already there, so rows loaded at launch enter normally and only later arrivals count as live.
        .onChange(of: monitor.lastUpdated) { if !feed.isSeeded { feed.seed(monitor.jobs.map(\.id)) } }
        .task {
            // Only while this tab is on screen: the server is ours, but there is no reason to ask when nobody looks.
            while !Task.isCancelled {
                await monitor.refresh()
                // Faster while a task is running: its gates change by the second.
                try? await Task.sleep(for: .seconds(monitor.activeCount > 0 ? 2 : 5))
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
                JobDot(status: job.status)
                Text(job.label).font(NothingTheme.small.weight(.semibold)).foregroundStyle(color(job))
                    .contentTransition(.opacity)
                    .resultPulse(["succeeded", "failed"].contains(job.status) ? job.status : "")
                    .animation(.smooth(duration: 0.3), value: job.status)
            }
            let attempt = job.attempts > 1 ? " · attempt \(job.attempts)" : ""
            Text("\(job.headSha.prefix(7))\(attempt) · \(Date(timeIntervalSince1970: Double(job.updatedAt) / 1000).formatted(.relative(presentation: .named)))")
                .font(NothingTheme.small).foregroundStyle(NothingTheme.inkDim)
            if job.report == nil, job.isActive {
                if let gates = job.progress, !gates.isEmpty {
                    VStack(alignment: .leading, spacing: 3) { ForEach(gates) { gateRow($0) } }.padding(.top, 4)
                } else if let activity = job.activity {
                    Text("Now: \(activity)").font(NothingTheme.small).foregroundStyle(NothingTheme.green).textSelection(.enabled)
                        .contentTransition(.opacity).animation(.smooth(duration: 0.3), value: activity)
                }
            }
            if let summary = job.report?.summary, !summary.isEmpty {
                Text(summary).font(NothingTheme.small).foregroundStyle(NothingTheme.inkDim).textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .nothingRow(fresh: feed.fresh.contains(job.id), tint: color(job), changeToken: job.status)
    }

    /// One gate of a running task: a mark for its state, its name, and while it runs what it is doing right now.
    private func gateRow(_ gate: GateJob.Gate) -> some View {
        let tint: Color = switch gate.state {
        case "passed": NothingTheme.green
        case "failed": NothingTheme.red
        case "running": NothingTheme.amber
        default: NothingTheme.inkDim
        }
        let mark = switch gate.state {
        case "passed": "✓"
        case "failed": "✗"
        case "running": "▸"
        default: "·"
        }
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(mark).foregroundStyle(tint).frame(width: 12)
            Text(gate.id).foregroundStyle(gate.state == "pending" ? NothingTheme.inkDim : NothingTheme.ink)
            if !gate.live.isEmpty {
                Text(gate.live).foregroundStyle(NothingTheme.inkDim).lineLimit(1).truncationMode(.middle)
                    .contentTransition(.opacity).animation(.smooth(duration: 0.25), value: gate.live)
            }
        }
        .font(NothingTheme.small)
        .animation(.smooth(duration: 0.3), value: gate.state)
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
