import SwiftUI

extension ProjectCIPanel {
  @ViewBuilder
  func codeLinterStatusRow(script: AutomationScript, workflow: GitHubWorkflow) -> some View {
    HStack(spacing: 8) {
      Image(
        systemName: codeLinterStatus == .latest
          ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
      )
      .foregroundStyle(codeLinterStatus == .latest ? .green : .orange)
      Text("Code Linter: \(codeLinterStatus.title)")
        .font(.caption)
        .foregroundStyle(.secondary)
      Spacer()
      if codeLinterStatus == .pinned {
        Button("Update to latest") {
          installViewModel.install(
            script: script.workflowOnly,
            project: project,
            variableValues: [:],
            mode: .localRunner
          )
        }
        .font(.caption.weight(.semibold))
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help(
          "Creates a PR that updates only \(workflow.path ?? "the Code Linter workflow") to @main.")
      }
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 7)
    .background(Color.secondary.opacity(0.055))
    .clipShape(RoundedRectangle(cornerRadius: 7))
  }

  var codeLinterScript: AutomationScript? {
    scripts.first(where: \.isCodeLinter)
  }

  var codeLinterWorkflowPath: String? {
    codeLinterScript?.matchingWorkflow(in: snapshot)?.path
  }

  func refreshCodeLinterStatus() async {
    guard let script = codeLinterScript, let path = codeLinterWorkflowPath else {
      codeLinterStatus = .unavailable
      return
    }
    let service = ProjectCIService(config: DashboardConfig())
    codeLinterStatus = script.codeLinterStatus(
      workflowSource: await service.workflowSource(for: project, path: path))
  }
}
