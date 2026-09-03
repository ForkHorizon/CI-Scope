import Foundation

// Emergency fallbacks used when the bundled JSON seeds are missing.
extension AutomationScriptSeedProvider {
    static func fallbackCodeLinterSeed() -> AutomationScript {
        AutomationScript(
            id: "code-linter",
            title: "Code Linter",
            summary: "Checks file & function length, nesting depth, parameter counts, comment blocks, and type counts.",
            detail: "Installs a GitHub workflow that calls the shared Code Linter in ForkHorizon/ci-gates.",
            runnerLabels: ["self-hosted", "macOS", "ARM64", "ci-scope"],
            branchName: "ci-scope/install-{{script_id}}",
            commitMessage: "Add {{script_title}}",
            pullRequestTitle: "Add {{script_title}}",
            pullRequestBody: fallbackPullRequestBody,
            variables: fallbackVariables,
            files: fallbackFiles,
            defaultSeedID: "code-linter"
        )
    }

    static func fallbackSwiftQualityGateSeed() -> AutomationScript {
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

    static func fallbackSwiftCompileGateSeed() -> AutomationScript {
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

    /// The caller workflow passes `config: .{{script_slug}}.json`, so the config
    /// has to ship with it — without it the six tunable limits are written to a
    /// file nobody reads and the gate silently runs on the linter's defaults.
    static var fallbackFiles: [AutomationScriptFile] {
        [
            AutomationScriptFile(
                id: "config",
                destinationPath: ".{{script_slug}}.json",
                isExecutable: false,
                contents: """
                    {
                      "max_file_lines": {{max_file_lines}},
                      "max_function_lines": {{max_function_lines}},
                      "max_nesting_depth": {{max_nesting_depth}},
                      "max_parameters": {{max_parameters}},
                      "max_comment_lines": {{max_comment_lines}},
                      "max_types_per_file": {{max_types_per_file}}
                    }

                    """
            ),
            AutomationScriptFile(
                id: "workflow",
                destinationPath: ".github/workflows/{{script_slug}}.yml",
                isExecutable: false,
                contents: fallbackWorkflow
            ),
        ]
    }

    static var fallbackSwiftQualityFiles: [AutomationScriptFile] {
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
                      "periphery_arguments": ["--retain-codable-properties"]
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

    static var fallbackSwiftCompileGateFiles: [AutomationScriptFile] {
        [
            AutomationScriptFile(
                id: "workflow",
                destinationPath: ".github/workflows/{{script_slug}}.yml",
                isExecutable: false,
                contents: fallbackCallerWorkflow(jobID: "swift-compile-gate", gate: "swift-compile.yml")
            )
        ]
    }

    static var fallbackWorkflow: String {
        fallbackCallerWorkflow(jobID: "code-linter", gate: "code-linter.yml")
    }

    static func fallbackCallerWorkflow(jobID: String, gate: String, withConfig: Bool = true) -> String {
        let runnerInputs =
            jobID == "slop-review"
            ? "      runner-group: Default\n      runner-labels: '[\\\"self-hosted\\\", \\\"macOS\\\", \\\"ARM64\\\", \\\"ci-scope-ai\\\"]'\n      runner-label: ci-scope-ai"
            : "      runs-on: '{{runner_labels_json}}'"
        return """
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
            \(withConfig ? "      config: .{{script_slug}}.json\n" : "")\(jobID == "code-linter" ? "      gates-ref: main\n" : "")\(runnerInputs)

            """
    }

    /// Shared shape for gates that are just one caller workflow file plus the generic PR body.
    static func fallbackSimpleGateSeed(
        _ blurb: GateBlurb,
        gate: String,
        withConfig: Bool = false
    ) -> AutomationScript {
        let id = blurb.id
        return AutomationScript(
            id: id,
            title: blurb.title,
            summary: blurb.summary,
            detail: blurb.detail,
            runnerLabels: id == "slop-review"
                ? ["self-hosted", "macOS", "ARM64", "ci-scope-ai"]
                : ["self-hosted", "macOS", "ARM64", "ci-scope"],
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
                    contents: fallbackCallerWorkflow(jobID: id, gate: gate, withConfig: withConfig)
                )
            ],
            defaultSeedID: id
        )
    }

    static func fallbackWebQualityGateSeed() -> AutomationScript {
        fallbackSimpleGateSeed(
            GateBlurb(
                id: "web-quality-gate",
                title: "Web Quality Gate",
                summary: "Typechecks TS/JS and blocks dead code, unused dependencies, and copy-paste.",
                detail: "Installs a workflow calling the shared ci-gates web gate: tsc, ESLint, knip, jscpd."
            ),
            gate: "web-quality.yml"
        )
    }

    static func fallbackUnityQualityGateSeed() -> AutomationScript {
        fallbackSimpleGateSeed(
            GateBlurb(
                id: "unity-quality-gate",
                title: "Unity Quality Gate",
                summary: "Compiles Unity C# with analyzers and blocks warnings and copy-paste in first-party code.",
                detail: "Installs a workflow calling the shared ci-gates Unity gate: dotnet build with analyzers, jscpd."
            ),
            gate: "unity-quality.yml",
            withConfig: true
        )
    }

    static func fallbackPythonQualityGateSeed() -> AutomationScript {
        fallbackSimpleGateSeed(
            GateBlurb(
                id: "python-quality-gate",
                title: "Python Quality Gate",
                summary: "Runs ruff lint and format checks with a strict anti-slop fallback config.",
                detail: "Installs a workflow calling the shared ci-gates Python gate: ruff check and format."
            ),
            gate: "python-quality.yml"
        )
    }

    static func fallbackGoQualityGateSeed() -> AutomationScript {
        fallbackSimpleGateSeed(
            GateBlurb(
                id: "go-quality-gate",
                title: "Go Quality Gate",
                summary: "Runs go vet, gofmt, and golangci-lint.",
                detail: "Installs a workflow calling the shared ci-gates Go gate: vet, format, lint (no go test)."
            ),
            gate: "go-quality.yml"
        )
    }

    static func fallbackSlopReviewSeed() -> AutomationScript {
        fallbackSimpleGateSeed(
            GateBlurb(
                id: "slop-review",
                title: "Slop Review",
                summary: "Advisory DeepSeek LLM review of PR diffs for AI-slop; never blocks the merge.",
                detail: "Installs a workflow calling the shared advisory ci-gates slop reviewer using DeepSeek."
            ),
            gate: "slop-review.yml"
        )
    }

    static var fallbackPullRequestBody: String {
        """
        Adds {{script_title}} managed by CI Scope.
        """
    }

    static var fallbackSwiftQualityPullRequestBody: String {
        """
        Adds {{script_title}} managed by CI Scope.

        This PR adds a Swift workflow with build, format, and dead-code gates.
        """
    }

    static var fallbackSwiftCompileGatePullRequestBody: String {
        """
        Adds {{script_title}} managed by CI Scope.

        This PR adds a Swift workflow that compiles the project and blocks configured critical warnings.
        """
    }
}
