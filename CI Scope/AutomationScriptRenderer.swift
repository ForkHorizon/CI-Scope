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
            let value = variableValues[variable.id] ?? variable.defaultValue
            result[variable.id] = variable.id == "gates_sha" ? value.trimmed : value
        }
        return result
    }

    private func builtInPlaceholders() -> [String: String] {
        let labels = runnerLabelsOverride ?? script.runnerLabels
        return [
            "repository_slug": project.repositorySlug,
            "repository_owner": project.repositoryOwner,
            "repository_name": project.repositoryName,
            "runner_labels": labels.joined(separator: ", "),
            "runner_labels_json": jsonLabelArray(labels),
            "default_branch": defaultBranch,
            "script_id": script.id,
            "script_slug": script.scriptSlug,
            "script_title": script.title,
            "script_summary": script.summary,
        ]
    }

    private func jsonLabelArray(_ labels: [String]) -> String {
        guard let data = try? JSONEncoder().encode(labels) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }

    private func resolvedVariableValues() -> [String: String] {
        var result: [String: String] = [:]
        for variable in script.variables {
            result[variable.id] = variableValues[variable.id] ?? variable.defaultValue
        }
        return result
    }
}
