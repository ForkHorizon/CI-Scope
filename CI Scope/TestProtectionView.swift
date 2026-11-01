import SwiftUI

/// Test protection tab: open alerts on the left, the selected alert with its actions on the right,
/// and the decision history below. Approve needs the owner's Touch ID; mute is local to this Mac.
struct TestProtectionView: View {
    @ObservedObject var model: TestProtectionViewModel
    let projects: [CIProject]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    alertList.frame(maxWidth: 260)
                    detail
                }
                if let message = model.message {
                    Text(message).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
                }
                historySection
            }
            .padding(14)
        }
        .task { await model.load(projects: projects) }
    }

    private var alertList: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.isLoading { ProgressView().controlSize(.small) }
            if model.openAlerts.isEmpty && !model.isLoading {
                Text("No open alerts. Weakened tests in accepted commits show up here.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(model.openAlerts) { alert in
                TestAlertRow(alert: alert, isSelected: alert.id == model.selected?.id)
                    .onTapGesture { model.selectedID = alert.id }
            }
        }
    }

    @ViewBuilder private var detail: some View {
        if let alert = model.selected {
            TestAlertCard(alert: alert, isBusy: model.isActing, actions: actions(for: alert))
        }
    }

    private func actions(for alert: TestAlert) -> TestAlertActions {
        TestAlertActions(
            revert: { Task { await model.revertAlert(alert) } },
            approve: { Task { await model.approve(alert) } },
            mute: { model.mute(alert) },
            openCommit: {
                if let url = URL(string: "https://github.com/\(alert.repository)/commit/\(alert.sha)") {
                    NSWorkspace.shared.open(url)
                }
            })
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("History", systemImage: "clock.arrow.circlepath").font(.callout.weight(.semibold))
            if model.history.isEmpty {
                Text("Decisions you make are recorded here.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(model.history.prefix(30), id: \.decidedAt) { item in
                Text("\(item.decision.capitalized) · \(item.repository) · \(item.sha.prefix(7)) · \(item.decidedAt)")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct TestAlertActions {
    let revert: () -> Void
    let approve: () -> Void
    let mute: () -> Void
    let openCommit: () -> Void
}

struct TestAlertRow: View {
    let alert: TestAlert
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(alert.repository.split(separator: "/").last.map(String.init) ?? alert.repository)
                    .font(.callout.weight(.semibold))
                Spacer()
                Text(alert.severity == .high ? "High" : "Medium")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(alert.severity == .high ? Color.red : Color.orange)
            }
            Text(alert.title).font(.caption).foregroundStyle(.secondary)
            Text("\(alert.findings.first?.path ?? "") · \(alert.shortSHA)")
                .font(.caption2).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(isSelected ? 0.14 : 0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }
}

struct TestAlertCard: View {
    let alert: TestAlert
    let isBusy: Bool
    let actions: TestAlertActions

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(alert.title).font(.headline)
                    Text("\(alert.repository) · commit \(alert.shortSHA)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Open commit", action: actions.openCommit).buttonStyle(.link).font(.caption)
            }
            Text(alert.message).font(.callout)
            ForEach(alert.findings, id: \.path) { finding in
                Text("\(finding.path): \(finding.message)")
                    .font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Text("No approval is recorded for this commit. Approving applies to this commit only; a new push raises the alert again.")
                .font(.caption2).foregroundStyle(.secondary)
            HStack {
                Button("Revert in PR", systemImage: "arrow.uturn.backward", action: actions.revert)
                Button("Approve this commit", systemImage: "touchid", action: actions.approve)
                Spacer()
                Button("Mute 24 h", action: actions.mute).foregroundStyle(.secondary)
                if isBusy { ProgressView().controlSize(.small) }
            }
            .disabled(isBusy)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
