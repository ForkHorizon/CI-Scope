import Foundation

extension ProjectCIService {
  /// Workflow files that actually exist on the repo's default branch.
  ///
  /// `gh workflow list` answers "what workflows does GitHub know about", which
  /// includes any workflow that has ever run on a side branch — so a gate
  /// sitting in an unmerged install PR reads as already installed. The
  /// coverage matrix is asking a narrower question, so it asks the contents
  /// API instead. One call, no clone, and nothing else in the app changes.
  func defaultBranchWorkflows(for project: CIProject) async -> [GitHubWorkflow] {
    if await GitHubRateLimitGate.shared.isPaused() { return [] }
    let command = """
      gh api \(quoted("repos/\(project.repositorySlug)/contents/.github/workflows")) \
        --jq '.[] | select(.type == "file") | .path'
      """
    let result = await ShellClient.run(command, timeout: 15, config: config)
    await GitHubRateLimitGate.shared.note(result: result, config: config)
    guard result.exitCode == 0 else { return [] }

    return result.output
      .components(separatedBy: .newlines)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { $0.hasSuffix(".yml") || $0.hasSuffix(".yaml") }
      .map { path in
        GitHubWorkflow(
          id: "default-branch:\(project.normalizedSlug):\(path)",
          name: workflowName(from: path),
          path: path,
          state: "active"
        )
      }
  }
}
