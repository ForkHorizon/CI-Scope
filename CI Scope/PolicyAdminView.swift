import SwiftUI

/// The Policy tab: pending policy PRs (merge + activate behind Touch ID) and the
/// per-project check editor. Nothing here needs the terminal or a typed secret.
struct PolicyAdminView: View {
    @ObservedObject var admin: PolicyAdminViewModel
    @ObservedObject var checks: PolicyChecksViewModel
    let projects: [CIProject]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                pendingSection
                PolicyChecksView(viewModel: checks, admin: admin, projects: projects)
            }
            .padding(14)
        }
        .task { await admin.load(projects: projects) }
    }

    private var pendingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Pending policy changes", systemImage: "touchid")
                    .font(.callout.weight(.semibold))
                Spacer()
                if admin.isLoading { ProgressView().controlSize(.small) }
                Button("Approve all") { Task { await admin.approveAll() } }
                    .disabled(admin.isApproving || admin.pendingCount == 0)
            }
            if admin.changes.isEmpty && !admin.isLoading {
                Text("Nothing waiting. Protected-file changes (manifest, workflows) show up here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(admin.changes) { change in
                PolicyChangeRow(change: change, status: admin.statuses[change.id], isBusy: admin.isApproving) {
                    Task { await admin.approve(change) }
                }
            }
            if let message = admin.message {
                Text(message).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
            }
            Text("Approving merges the PR with admin bypass, then signs the new policy. Touch ID is asked once per batch.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct PolicyChangeRow: View {
    let change: PolicyPullRequest
    let status: PolicyChangeStatus?
    let isBusy: Bool
    let onApprove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            StatusDot(state: dotState)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 2) {
                if let url = URL(string: change.url) {
                    Link("\(change.repository)#\(change.number)", destination: url)
                        .font(.caption.weight(.semibold))
                }
                Text("\(change.title) → \(change.baseRefName)")
                    .font(.caption)
                    .lineLimit(1)
                Text(statusText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
            if status?.needsApproval ?? false || isFailed {
                Button(isFailed ? "Retry" : "Approve", action: onApprove)
                    .disabled(isBusy)
            }
        }
    }

    private var isFailed: Bool {
        if case .failed = status { return true }
        return false
    }

    private var dotState: ServiceState {
        switch status {
        case .active: .online
        case .failed: .offline
        case .working, .awaitingMerge, .awaitingActivation: .warning
        case nil: .unknown
        }
    }

    private var statusText: String {
        switch status {
        case .awaitingMerge: "Waiting for approval (its CI check fails until then; that's expected)"
        case .awaitingActivation: "Merged, but the new policy isn't active yet"
        case .active: "Active"
        case .working(let step): step
        case .failed(let reason): reason
        case nil: "Checking…"
        }
    }
}
