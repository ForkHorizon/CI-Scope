// Open security events: tampering attempts and merges without a green check.
import SwiftUI

struct AlertsView: View {
    @ObservedObject var events: SecurityEventMonitor
    @State private var feed = FreshSet<Int>()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if events.events.isEmpty {
                    Text("All clear. Nothing needs your attention.").font(NothingTheme.body).foregroundStyle(NothingTheme.inkDim)
                }
                ForEach(Array(events.events.enumerated()), id: \.element.id) { index, event in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title).font(NothingTheme.body.weight(.semibold)).foregroundStyle(NothingTheme.red)
                        Text("\(event.repository) · \(event.detail)").font(NothingTheme.small).foregroundStyle(NothingTheme.inkDim)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .nothingRow(fresh: feed.fresh.contains(event.id), tint: NothingTheme.red)
                    .nothingEntrance(index)
                }
                HStack(spacing: 10) {
                    if !events.events.isEmpty {
                        Button("Acknowledge all") { Task { await events.acknowledgeAll() } }.buttonStyle(.pillPrimary)
                    }
                    Button("Open on website") { NSWorkspace.shared.open(ServerLinks.alerts) }.buttonStyle(.pill)
                }
                if let message = events.message {
                    Text(message).font(NothingTheme.small).foregroundStyle(NothingTheme.amber).textSelection(.enabled)
                }
            }
            .padding(22)
            .animation(.smooth(duration: 0.35), value: events.events.map(\.id))
        }
        .onAppear { feed.seed(events.events.map(\.id)) }
        .onChange(of: events.events.map(\.id)) { _, ids in feed.update(ids) }
    }
}
