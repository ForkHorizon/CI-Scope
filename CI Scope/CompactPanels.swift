import SwiftUI

struct RunRow: View {
    let run: GitHubRun

    var body: some View {
        HStack(spacing: 9) {
            StatusDot(state: state)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(run.displayTitle)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text(run.compactConclusion)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(color)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    Text(run.workflowName)
                    Text("·")
                    Text(run.headBranch)
                    Text("·")
                    Text(shortDate(run.createdAt))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(Color.secondary.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    var state: ServiceState {
        if run.conclusion == "success" { return .online }
        if run.status != "completed" { return .warning }
        return .offline
    }

    var color: Color {
        switch state {
        case .online: .green
        case .warning: .orange
        case .offline: .red
        case .unknown: .secondary
        }
    }

    func shortDate(_ value: String) -> String {
        value
            .replacingOccurrences(of: "T", with: " ")
            .replacingOccurrences(of: "Z", with: "")
    }
}
