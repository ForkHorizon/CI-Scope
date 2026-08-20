import SwiftUI

struct ProjectWorkflowList: View {
  let workflows: [GitHubWorkflow]

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      Text("Workflows")
        .font(.callout.weight(.semibold))
        .foregroundStyle(.secondary)

      ForEach(workflows) { workflow in
        HStack(spacing: 8) {
          StatusDot(state: workflow.state.lowercased().contains("disabled") ? .warning : .online)
          VStack(alignment: .leading, spacing: 2) {
            Text(workflow.name)
              .font(.callout.weight(.semibold))
              .lineLimit(1)
            Text(workflow.path ?? workflow.state)
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(1)
              .truncationMode(.middle)
          }
          Spacer()
          Text(workflow.state)
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(Color.secondary.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 7))
      }
    }
  }
}

struct ProjectRunList: View {
  let runs: [GitHubRun]

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      Text("Recent Runs")
        .font(.callout.weight(.semibold))
        .foregroundStyle(.secondary)

      ForEach(runs.prefix(8)) { run in
        Link(destination: URL(string: run.url)!) {
          RunRow(run: run)
        }
        .buttonStyle(.plain)
      }
    }
  }
}
