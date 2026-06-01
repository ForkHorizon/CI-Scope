import Foundation

enum AutomationScriptSeedProvider {
    static let defaultSeedIDs = ["ai-readability", "swift-quality-gate"]

    static func loadDefaultScripts() throws -> [AutomationScript] {
        try defaultSeedIDs.map { try loadSeed($0) }
    }

    static func loadSeed(_ id: String) throws -> AutomationScript {
        if let script = try loadBundledSeed(id) {
            return script
        }
        switch id {
        case "ai-readability":
            return fallbackReadabilitySeed()
        case "swift-quality-gate":
            return fallbackSwiftQualityGateSeed()
        default:
            throw AutomationScriptError.missingSeed(id)
        }
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
            title: "Linter Checker 300 Lines",
            summary: "Checks max source file length and function length.",
            detail: "Installs a GitHub workflow, JSON config, and Python checker.",
            runnerLabels: ["self-hosted", "macOS", "ARM64", "ci-scope"],
            branchName: "ci-scope/install-{{script_id}}",
            commitMessage: "Add {{script_title}}",
            pullRequestTitle: "Add {{script_title}}",
            pullRequestBody: fallbackPullRequestBody,
            variables: fallbackVariables,
            files: fallbackFiles,
            defaultSeedID: "ai-readability"
        )
    }

    private static func fallbackSwiftQualityGateSeed() -> AutomationScript {
        AutomationScript(
            id: "swift-quality-gate",
            title: "Swift Quality Gate",
            summary: "Builds Swift projects and blocks formatting and dead-code regressions.",
            detail: "Installs a Swift CI workflow, JSON config, swift-format config, and Python driver.",
            runnerLabels: ["self-hosted", "macOS", "ARM64", "ci-scope"],
            branchName: "ci-scope/install-{{script_id}}",
            commitMessage: "Add {{script_title}}",
            pullRequestTitle: "Add {{script_title}}",
            pullRequestBody: fallbackSwiftQualityPullRequestBody,
            variables: [],
            files: fallbackSwiftQualityFiles,
            defaultSeedID: "swift-quality-gate"
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
            ),
        ]
    }

    private static var fallbackFiles: [AutomationScriptFile] {
        [
            AutomationScriptFile(
                id: "workflow",
                destinationPath: ".github/workflows/{{script_slug}}.yml",
                isExecutable: false,
                contents: fallbackWorkflow
            )
        ]
    }

    private static var fallbackSwiftQualityFiles: [AutomationScriptFile] {
        [
            AutomationScriptFile(
                id: "config",
                destinationPath: ".{{script_slug}}.json",
                isExecutable: false,
                contents: """
                    {
                      "xcode_workspace": "",
                      "xcode_project": "",
                      "xcode_scheme": "",
                      "xcode_destination": "generic/platform=macOS",
                      "xcode_configuration": "Debug",
                      "swift_format_config": ".swift-format",
                      "fallback_swift_format_config": ".ci-scope-swift-format.json",
                      "dead_code_enabled": true,
                      "dead_code_install_periphery": true,
                      "periphery_arguments": []
                    }

                    """
            ),
            AutomationScriptFile(
                id: "swift-format-config",
                destinationPath: ".ci-scope-swift-format.json",
                isExecutable: false,
                contents: """
                    {
                      "indentation": {
                        "spaces": 4
                      },
                      "lineLength": 140,
                      "version": 1
                    }

                    """
            ),
            AutomationScriptFile(
                id: "workflow",
                destinationPath: ".github/workflows/{{script_slug}}.yml",
                isExecutable: false,
                contents: """
                    name: {{script_title}}

                    on:
                      pull_request:
                      workflow_dispatch:

                    jobs:
                      swift-quality-gate:
                        name: {{script_title}}
                        runs-on: [{{runner_labels}}]
                        steps:
                          - uses: actions/checkout@v6
                          - run: python3 scripts/{{script_slug}}.py --config .{{script_slug}}.json --stage all --mode all

                    """
            ),
            AutomationScriptFile(
                id: "checker",
                destinationPath: "scripts/{{script_slug}}.py",
                isExecutable: true,
                contents: """
                    #!/usr/bin/env python3
                    import sys

                    print("::error::Bundled Swift Quality Gate seed is missing. Reinstall or rebuild CI Scope.")
                    sys.exit(2)

                    """
            ),
        ]
    }

    private static var fallbackWorkflow: String {
        """
        name: {{script_title}}

        on:
          pull_request:
          workflow_dispatch:

        jobs:
          readability:
            name: {{script_title}}
            runs-on: [{{runner_labels}}]
            steps:
              - uses: actions/checkout@v6
              - run: python3 scripts/{{script_slug}}.py --config .{{script_slug}}.json --mode all
        """
    }

    private static var fallbackPullRequestBody: String {
        """
        Adds {{script_title}} managed by CI Scope.
        """
    }

    private static var fallbackSwiftQualityPullRequestBody: String {
        """
        Adds {{script_title}} managed by CI Scope.

        This PR adds a Swift workflow with build, format, and dead-code gates.
        """
    }
}
