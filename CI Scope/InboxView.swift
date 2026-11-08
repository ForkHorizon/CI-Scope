// Protected-file and test-edit change requests across all projects: reject here, approve on the website (passkey).
import SwiftUI

struct InboxView: View {
    @ObservedObject var inbox: ChangeRequestMonitor

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if inbox.pending.isEmpty {
                    Text("No pending requests.").font(NothingTheme.body).foregroundStyle(NothingTheme.inkDim)
                }
                ForEach(inbox.pendingByRepository, id: \.repository) { group in
                    Text(group.repository).nothingCaption()
                    ForEach(group.requests) { request in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(request.title)
                                .font(NothingTheme.body.weight(.semibold)).foregroundStyle(NothingTheme.amber)
                            if request.isTestEdit, let reason = request.reason {
                                Text("Why: \(reason)").font(NothingTheme.small).foregroundStyle(NothingTheme.ink)
                            }
                            ForEach(request.items, id: \.path) { item in
                                Text("\(item.kind) · \(item.path)").font(NothingTheme.small).foregroundStyle(NothingTheme.inkDim)
                            }
                            HStack(spacing: 10) {
                                Button("Open in website to approve") { NSWorkspace.shared.open(ServerLinks.inbox) }.buttonStyle(.pillPrimary)
                                Button("Reject") { Task { await inbox.reject(request) } }.buttonStyle(.pill)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .nothingRow(fresh: false, tint: NothingTheme.amber)
                    }
                }
                HStack(spacing: 10) {
                    Button("Refresh") { Task { await inbox.refresh() } }.buttonStyle(.pill)
                    Button("Open on website") { NSWorkspace.shared.open(ServerLinks.inbox) }.buttonStyle(.pill)
                }
                if let message = inbox.message {
                    Text(message).font(NothingTheme.small).foregroundStyle(NothingTheme.amber).textSelection(.enabled)
                }
            }
            .padding(22)
        }
        .onAppear { Task { await inbox.refresh() } }
    }
}
