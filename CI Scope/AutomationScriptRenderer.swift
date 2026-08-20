import Foundation

struct AutomationScriptRenderer {
  let script: AutomationScript
  let project: CIProject
  let variableValues: [String: String]
  let defaultBranch: String
  var runnerLabelsOverride: [String]? = nil

  var branchName: String {
    render(script.branchName)
  }

  var commitMessage: String {
    render(script.commitMessage)
  }

  var pullRequestTitle: String {
    render(script.pullRequestTitle)
  }

  var pullRequestBody: String {
    render(script.pullRequestBody)
  }

  func renderedFiles() throws -> [AutomationScriptFile] {
    try script.files.map { file in
      try AutomationScriptValidator.validatePath(render(file.destinationPath))
      return AutomationScriptFile(
        id: file.id,
        destinationPath: render(file.destinationPath),
        isExecutable: file.isExecutable,
        contents: render(file.contents)
      )
    }
  }

  func validate() throws {
    try AutomationScriptValidator.validateForInstall(
      script,
      values: resolvedVariableValues(),
      branchName: branchName
    )
  }

  private func render(_ text: String) -> String {
    placeholders().reduce(text) { result, item in
      result.replacingOccurrences(of: "{{\(item.key)}}", with: item.value)
    }
  }

  private func placeholders() -> [String: String] {
    var result = builtInPlaceholders()
    for variable in script.variables {
      result[variable.id] = variableValues[variable.id] ?? variable.defaultValue
    }
    return result
  }

  private func builtInPlaceholders() -> [String: String] {
    [
      "repository_slug": project.repositorySlug,
      "repository_owner": project.repositoryOwner,
      "repository_name": project.repositoryName,
      "runner_labels": (runnerLabelsOverride ?? script.runnerLabels).joined(separator: ", "),
      "runner_labels_json": jsonLabelArray(runnerLabelsOverride ?? script.runnerLabels),
      "default_branch": defaultBranch,
      "script_id": script.id,
      "script_slug": script.scriptSlug,
      "script_title": script.title,
      "script_summary": script.summary,
    ]
  }

  private func jsonLabelArray(_ labels: [String]) -> String {
    "[" + labels.map { "\"\($0)\"" }.joined(separator: ", ") + "]"
  }

  private func resolvedVariableValues() -> [String: String] {
    var result: [String: String] = [:]
    for variable in script.variables {
      result[variable.id] = variableValues[variable.id] ?? variable.defaultValue
    }
    return result
  }
}
