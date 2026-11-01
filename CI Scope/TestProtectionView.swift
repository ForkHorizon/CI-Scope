import SwiftUI

/// Test protection tab: open alerts on the left, the selected alert with its actions on the right,
/// and the decision history below. Approve needs the owner's Touch ID; mute is local to this Mac.
struct TestProtectionView: View {
    @ObservedObject var model: TestProtectionViewModel
    let projects: [CIProject]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero
                HStack(alignment: .top, spacing: 16) {
                    alertList.frame(maxWidth: 280)
                    detail
                }
                if let message = model.message {
                    Text(message).font(NothingTheme.small).foregroundStyle(.orange).textSelection(.enabled)
                }
                historySection
            }
            .padding(22)
        }
        .task { await model.load(projects: projects) }
    }

    private var hero: some View {
        let high = model.openAlerts.filter { $0.severity == .high }.count
        return HStack(alignment: .bottom, spacing: 28) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Open alerts").nothingCaption()
                Text("\(model.openAlerts.count)").nothingDisplay(72).foregroundStyle(NothingTheme.ink)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("High").nothingCaption()
                Text("\(high)").nothingDisplay(40)
                    .foregroundStyle(high > 0 ? NothingTheme.red : NothingTheme.inkDim)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Other").nothingCaption()
                Text("\(model.openAlerts.count - high)").nothingDisplay(40).foregroundStyle(NothingTheme.inkDim)
            }
            Spacer()
            if model.isLoading { ProgressView().controlSize(.small) }
        }
    }

    private var alertList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Alerts").nothingCaption().padding(.bottom, 2)
            if model.openAlerts.isEmpty && !model.isLoading {
                Text("No open alerts. Weakened tests in accepted commits show up here.")
                    .font(NothingTheme.small).foregroundStyle(NothingTheme.inkDim)
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

    private static func summary(of item: TestDecision) -> String {
        let parts: [String?] = [
            item.decision.capitalized, item.repository, String(item.sha.prefix(7)), "by \(item.decidedBy)",
            item.path, item.note, item.decidedAt,
        ]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("History").nothingCaption()
            if model.history.isEmpty {
                Text("Decisions you make are recorded here.").font(NothingTheme.small).foregroundStyle(NothingTheme.inkDim)
            }
            ForEach(model.history.prefix(30), id: \.decidedAt) { item in
                Text(Self.summary(of: item))
                    .font(NothingTheme.small).foregroundStyle(NothingTheme.inkDim).lineLimit(1).truncationMode(.middle)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nothingCard()
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
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(alert.severity == .high ? NothingTheme.red : Color.clear)
                .overlay(Circle().stroke(alert.severity == .high ? NothingTheme.red : NothingTheme.lineStrong, lineWidth: 1))
                .frame(width: 8, height: 8)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 3) {
                Text(alert.repository.split(separator: "/").last.map(String.init) ?? alert.repository)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                Text(alert.title).font(.system(size: 11, design: .monospaced)).foregroundStyle(NothingTheme.inkDim)
                Text("\(alert.findings.first?.path ?? "") · \(alert.shortSHA)")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(NothingTheme.inkDim.opacity(0.7))
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nothingCard(radius: 12, highlighted: isSelected)
        .contentShape(Rectangle())
    }
}

struct TestAlertCard: View {
    let alert: TestAlert
    let isBusy: Bool
    let actions: TestAlertActions

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(alert.repository) · \(alert.shortSHA)").nothingCaption()
            Text(alert.title).nothingDisplay(26).lineLimit(2)
            Text(alert.message).font(.system(size: 12, design: .monospaced))
            VStack(alignment: .leading, spacing: 4) {
                ForEach(alert.findings, id: \.path) { finding in
                    Text("\(finding.path): \(finding.message)")
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(NothingTheme.inkDim)
                        .textSelection(.enabled)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(white: 0.04), in: RoundedRectangle(cornerRadius: 10))
            Text("Approving applies to this commit only; a new push raises the alert again.")
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(NothingTheme.inkDim)
            HStack(spacing: 8) {
                Button("Approve", systemImage: "touchid", action: actions.approve).buttonStyle(.pillPrimary)
                Button("Revert", systemImage: "arrow.uturn.backward", action: actions.revert).buttonStyle(.pillDanger)
                if isBusy { ProgressView().controlSize(.small) }
            }
            .disabled(isBusy)
            HStack(spacing: 8) {
                Button("Mute 24 h", action: actions.mute).buttonStyle(.pill)
                Button("Open commit", action: actions.openCommit).buttonStyle(.pill)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nothingCard(radius: 18, highlighted: true)
    }
}
