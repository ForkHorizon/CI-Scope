import Foundation

enum AutomationScriptSeedProvider {
    static let defaultSeedIDs = ["ai-readability"]

    static func loadDefaultScripts() throws -> [AutomationScript] {
        try defaultSeedIDs.map { try loadSeed($0) }
    }

    static func loadSeed(_ id: String) throws -> AutomationScript {
        if let script = try loadBundledSeed(id) {
            return script
        }
        if id == "ai-readability" {
            return fallbackReadabilitySeed()
        }
        throw AutomationScriptError.missingSeed(id)
    }

    private static func loadBundledSeed(_ id: String) throws -> AutomationScript? {
        let nestedURL = Bundle.main.url(
            forResource: id,
            withExtension: "json",
            subdirectory: "AutomationScriptSeeds"
        )
        let rootURL = Bundle.main.url(forResource: id, withExtension: "json")
        guard let url = nestedURL ?? rootURL else {
            return nil
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(AutomationScript.self, from: data)
    }

    private static func fallbackReadabilitySeed() -> AutomationScript {
        AutomationScript(
            id: "ai-readability",
            title: "AI Readability",
            summary: "Checks file and function length for AI-readable code.",
            detail: "Installs a GitHub workflow, JSON config, and Python checker.",
            runnerLabels: ["self-hosted", "macOS", "ARM64", "ci-scope"],
            branchName: "ci-scope/install-{{script_id}}",
            commitMessage: "Add AI readability gate",
            pullRequestTitle: "Add AI readability gate",
            pullRequestBody: fallbackPullRequestBody,
            variables: fallbackVariables,
            files: fallbackFiles,
            defaultSeedID: "ai-readability"
        )
    }

    private static var fallbackVariables: [AutomationScriptVariable] {
        [
            AutomationScriptVariable(
                id: "max_file_lines",
                title: "Max file lines",
                kind: .number,
                isRequired: true,
                defaultValue: "300",
                help: "Largest allowed source file length.",
                options: []
            ),
            AutomationScriptVariable(
                id: "max_function_lines",
                title: "Max function lines",
                kind: .number,
                isRequired: true,
                defaultValue: "50",
                help: "Largest allowed function or method length.",
                options: []
            )
        ]
    }

    private static var fallbackFiles: [AutomationScriptFile] {
        [
            AutomationScriptFile(
                id: "workflow",
                destinationPath: ".github/workflows/ai-readability.yml",
                isExecutable: false,
                contents: fallbackWorkflow
            )
        ]
    }

    private static var fallbackWorkflow: String {
        """
        name: AI Readability

        on:
          pull_request:
          workflow_dispatch:

        jobs:
          readability:
            name: AI readability gate
            runs-on: [{{runner_labels}}]
            steps:
              - uses: actions/checkout@v6
              - run: python3 scripts/ai-readability-check.py --mode all
        """
    }

    private static var fallbackPullRequestBody: String {
        """
        Adds the portable AI Readability Gate managed by CI Scope.
        """
    }
}
