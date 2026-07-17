import Foundation

enum AutomationScriptSeedProvider {
    static let defaultSeedIDs = [
        "ai-readability", "swift-quality-gate", "swift-compile-gate",
        "web-quality-gate", "python-quality-gate",
    ]

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
        case "swift-compile-gate":
            return fallbackSwiftCompileGateSeed()
        case "web-quality-gate":
            return fallbackWebQualityGateSeed()
        case "python-quality-gate":
            return fallbackPythonQualityGateSeed()
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
            detail: "Installs a GitHub workflow that calls the shared readability gate in ForkHorizon/ci-gates.",
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
            detail: "Installs a Swift workflow calling the shared ci-gates quality gate, plus JSON and swift-format configs.",
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

    private static func fallbackSwiftCompileGateSeed() -> AutomationScript {
        AutomationScript(
            id: "swift-compile-gate",
            title: "Swift Compile Gate",
            summary: "Compiles Swift projects and blocks configured critical warnings.",
            detail: "Installs a Swift workflow that calls the shared compile gate in ForkHorizon/ci-gates.",
            runnerLabels: ["self-hosted", "macOS", "ARM64", "ci-scope"],
            branchName: "ci-scope/install-{{script_id}}",
            commitMessage: "Add {{script_title}}",
            pullRequestTitle: "Add {{script_title}}",
            pullRequestBody: fallbackSwiftCompileGatePullRequestBody,
            variables: [],
            files: fallbackSwiftCompileGateFiles,
            defaultSeedID: "swift-compile-gate"
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
                contents: fallbackCallerWorkflow(jobID: "swift-quality-gate", gate: "swift-quality.yml")
            ),
        ]
    }

    private static var fallbackSwiftCompileGateFiles: [AutomationScriptFile] {
        [
            AutomationScriptFile(
                id: "workflow",
                destinationPath: ".github/workflows/{{script_slug}}.yml",
                isExecutable: false,
                contents: fallbackCallerWorkflow(jobID: "swift-compile-gate", gate: "swift-compile.yml")
            )
        ]
    }

    private static var fallbackWorkflow: String {
        fallbackCallerWorkflow(jobID: "readability", gate: "readability.yml")
    }

    private static func fallbackCallerWorkflow(jobID: String, gate: String, withConfig: Bool = true) -> String {
        """
        name: {{script_title}}

        on:
          pull_request:
          workflow_dispatch:

        permissions:
          contents: read

        jobs:
          \(jobID):
            uses: ForkHorizon/ci-gates/.github/workflows/\(gate)@main
            with:
        \(withConfig ? "      config: .{{script_slug}}.json\n" : "")      runs-on: '{{runner_labels_json}}'

        """
    }

    private static func fallbackWebQualityGateSeed() -> AutomationScript {
        AutomationScript(
            id: "web-quality-gate",
            title: "Web Quality Gate",
            summary: "Typechecks TS/JS and blocks dead code, unused dependencies, and copy-paste.",
            detail: "Installs a workflow calling the shared ci-gates web gate: tsc, ESLint, knip, jscpd.",
            runnerLabels: ["self-hosted", "macOS", "ARM64", "ci-scope"],
            branchName: "ci-scope/install-{{script_id}}",
            commitMessage: "Add {{script_title}}",
            pullRequestTitle: "Add {{script_title}}",
            pullRequestBody: fallbackPullRequestBody,
            variables: [],
            files: [
                AutomationScriptFile(
                    id: "workflow",
                    destinationPath: ".github/workflows/{{script_slug}}.yml",
                    isExecutable: false,
                    contents: fallbackCallerWorkflow(jobID: "web-quality-gate", gate: "web-quality.yml", withConfig: false)
                )
            ],
            defaultSeedID: "web-quality-gate"
        )
    }

    private static func fallbackPythonQualityGateSeed() -> AutomationScript {
        AutomationScript(
            id: "python-quality-gate",
            title: "Python Quality Gate",
            summary: "Runs ruff lint and format checks with a strict anti-slop fallback config.",
            detail: "Installs a workflow calling the shared ci-gates Python gate: ruff check and format.",
            runnerLabels: ["self-hosted", "macOS", "ARM64", "ci-scope"],
            branchName: "ci-scope/install-{{script_id}}",
            commitMessage: "Add {{script_title}}",
            pullRequestTitle: "Add {{script_title}}",
            pullRequestBody: fallbackPullRequestBody,
            variables: [],
            files: [
                AutomationScriptFile(
                    id: "workflow",
                    destinationPath: ".github/workflows/{{script_slug}}.yml",
                    isExecutable: false,
                    contents: fallbackCallerWorkflow(
                        jobID: "python-quality-gate", gate: "python-quality.yml", withConfig: false)
                )
            ],
            defaultSeedID: "python-quality-gate"
        )
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

    private static var fallbackSwiftCompileGatePullRequestBody: String {
        """
        Adds {{script_title}} managed by CI Scope.

        This PR adds a Swift workflow that compiles the project and blocks configured critical warnings.
        """
    }
}
