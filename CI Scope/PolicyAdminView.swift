import SwiftUI

/// The Policy tab: pending policy PRs (merge + activate behind Touch ID) and the
/// per-project check editor. Nothing here needs the terminal or a typed secret.
struct PolicyAdminView: View {
    @ObservedObject var admin: PolicyAdminViewModel
    @ObservedObject var checks: PolicyChecksViewModel
    let projects: [CIProject]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                pendingSection
                PolicyChecksView(viewModel: checks, admin: admin, projects: projects)
            }
            .padding(22)
        }
        .task { await admin.load(projects: projects) }
    }

    private var pendingSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Waiting for Touch ID").nothingCaption()
                    Text("\(admin.pendingCount)")
                        .nothingDisplay(56)
                        .foregroundStyle(admin.pendingCount > 0 ? NothingTheme.amber : NothingTheme.inkDim)
                }
                Spacer()
                if admin.isLoading { ProgressView().controlSize(.small) }
                Button("Approve all") { Task { await admin.approveAll() } }
                    .buttonStyle(.pillPrimary)
                    .disabled(admin.isApproving || admin.pendingCount == 0)
            }
            if admin.changes.isEmpty && !admin.isLoading {
                Text("Nothing waiting. Protected-file changes (manifest, workflows) show up here.")
                    .font(NothingTheme.small)
                    .foregroundStyle(NothingTheme.inkDim)
            }
            VStack(spacing: 0) {
                ForEach(admin.changes) { change in
                    PolicyChangeRow(change: change, status: admin.statuses[change.id], isBusy: admin.isApproving) {
                        Task { await admin.approve(change) }
                    }
                }
            }
            if let message = admin.message {
                Text(message).font(NothingTheme.small).foregroundStyle(NothingTheme.amber).textSelection(.enabled)
            }
            Text("Approving merges the PR with admin bypass, then signs the new policy. Touch ID is asked once per batch.")
                .font(NothingTheme.tiny)
                .foregroundStyle(NothingTheme.inkDim)
        }
    }
}

struct PolicyChangeRow: View {
    let change: PolicyPullRequest
    let status: PolicyChangeStatus?
    let isBusy: Bool
    let onApprove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            StatusDot(state: dotState)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                if let url = URL(string: change.url) {
                    Link("\(change.repository)#\(change.number)", destination: url)
                        .font(NothingTheme.small.weight(.semibold))
                }
                Text("\(change.title) → \(change.baseRefName)")
                    .font(NothingTheme.small)
                    .lineLimit(1)
                Text(statusText)
                    .font(NothingTheme.tiny)
                    .foregroundStyle(NothingTheme.inkDim)
                    .textSelection(.enabled)
            }
            Spacer()
            if status?.needsApproval ?? false || isFailed {
                Button(isFailed ? "Retry" : "Approve", action: onApprove)
                    .buttonStyle(isFailed ? .pillDanger : .pillPrimary)
                    .disabled(isBusy)
            }
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(NothingTheme.line).frame(height: 1) }
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
