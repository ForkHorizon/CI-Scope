import SwiftUI

struct RunnerSubRunnerDisclosure: View {
    let subRunners: [RunnerSubRunnerSnapshot]

    var body: some View {
        if !subRunners.isEmpty {
            DisclosureGroup {
                VStack(spacing: 7) {
                    ForEach(subRunners) { subRunner in
                        RunnerSubRunnerRow(subRunner: subRunner)
                    }
                }
                .padding(.top, 8)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NothingTheme.inkDim)
                    Text("Sub-runners")
                        .font(NothingTheme.body.weight(.semibold))
                    Spacer()
                    Text("\(subRunners.count)")
                        .font(NothingTheme.small.monospacedDigit())
                        .foregroundStyle(NothingTheme.inkDim)
                }
            }
            .padding(9)
            .background(Color.secondary.opacity(0.045))
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
    }
}

private struct RunnerSubRunnerRow: View {
    let subRunner: RunnerSubRunnerSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Circle()
                    .fill(color(for: subRunner.state))
                    .frame(width: 7, height: 7)
                VStack(alignment: .leading, spacing: 1) {
                    Text(subRunner.title)
                        .font(NothingTheme.small.weight(.semibold))
                        .lineLimit(1)
                    Text(subRunner.scope)
                        .font(NothingTheme.tiny)
                        .foregroundStyle(NothingTheme.inkDim)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 8)
                RunnerStatePill(state: subRunner.state, text: subRunnerStateText)
            }

            HStack(spacing: 8) {
                RunnerMiniMetric(title: "Repos", value: "\(subRunner.visibleRepositoryCount)")
                RunnerMiniMetric(title: "Running", value: "\(subRunner.activeJobCount)")
                RunnerMiniMetric(title: "Queue", value: "\(subRunner.queuedJobCount)")
                Spacer(minLength: 0)
            }

            RunnerLabelStrip(labels: subRunner.labels)

            if let lastError = subRunner.lastError {
                RunnerWarningLine(text: lastError)
            }
        }
        .padding(9)
        .background(Color.secondary.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private var subRunnerStateText: String {
        if subRunner.activeJobCount > 0 { return "Running" }
        if subRunner.queuedJobCount > 0 { return "Queued" }
        if subRunner.state == .online { return "Ready" }
        return subRunner.state.rawValue
    }
}
