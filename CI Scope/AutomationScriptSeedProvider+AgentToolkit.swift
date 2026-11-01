import Foundation

extension AutomationScriptSeedProvider {
    /// ci-gates commit reviewed by the release owner (main after file-roles and agent-docs-stable).
    static let reviewedGatesSHA = "1e599f0b7451ffc334a823e5a4a78af122bef49e"

    static func fallbackAgentToolkitSeed() -> AutomationScript {
        AutomationScript(
            id: "agent-toolkit",
            title: "CI Scope Agent Toolkit",
            summary: "Runs local CI Scope checks from coding-agent hooks.",
            detail:
                "Adds scripts/check, a stack-profile manifest, and Claude Code hooks. The ci-gates checkout is pinned to a reviewed SHA.",
            runnerLabels: ["self-hosted", "macOS", "ARM64", "ci-scope"],
            branchName: "ci-scope/install-{{script_id}}",
            commitMessage: "Add {{script_title}}",
            pullRequestTitle: "Add {{script_title}}",
            pullRequestBody: "Adds local CI Scope checks pinned to ci-gates {{gates_sha}}.",
            variables: [
                AutomationScriptVariable(
                    id: "gates_sha", title: "Reviewed ci-gates SHA", kind: .text,
                    isRequired: true, defaultValue: reviewedGatesSHA,
                    help: "Full 40-character commit SHA containing the checks.", options: []),
                AutomationScriptVariable(
                    id: "stack_profile", title: "Stack profile", kind: .option,
                    isRequired: true, defaultValue: "ts-web",
                    help: "Select the repository's main language stack.", options: ["ts-web", "go", "python", "swift", "unity"]),
            ],
            files: agentToolkitFiles,
            defaultSeedID: "agent-toolkit"
        )
    }

    private static var agentToolkitFiles: [AutomationScriptFile] {
        [
            AutomationScriptFile(
                id: "check", destinationPath: "scripts/check", isExecutable: true,
                contents: """
                    #!/usr/bin/env bash
                    set -euo pipefail
                    gates_sha="{{gates_sha}}"
                    gates_root="${CI_SCOPE_GATES:-${HOME}/.ci-scope/gates}"
                    if [[ ! -x "$gates_root/scripts/check" && -z "${CI_SCOPE_GATES:-}" ]]; then
                      mkdir -p "$(dirname "$gates_root")"
                      { gh repo clone ForkHorizon/ci-gates "$gates_root" -- --quiet || git clone --quiet https://github.com/ForkHorizon/ci-gates "$gates_root"; } >&2 || true
                      git -C "$gates_root" checkout --quiet "$gates_sha" >&2 || true
                    fi
                    if [[ ! -x "$gates_root/scripts/check" ]]; then
                      echo "ci-gates is missing at $gates_root. Run: git clone https://github.com/ForkHorizon/ci-gates \"$gates_root\" && git -C \"$gates_root\" checkout {{gates_sha}}" >&2
                      exit 2
                    fi
                    actual_sha="$(git -C "$gates_root" rev-parse HEAD)"
                    if [[ "$actual_sha" != "$gates_sha" ]]; then
                      echo "ci-gates SHA mismatch: expected $gates_sha, found $actual_sha." >&2
                      exit 2
                    fi
                    if ! gates_status="$(git -C "$gates_root" status --porcelain --untracked-files=all)"; then
                      echo "Unable to verify ci-gates checkout status." >&2
                      exit 2
                    fi
                    if [[ -n "$gates_status" ]]; then
                      echo "ci-gates checkout has local changes; refusing to run unpinned code." >&2
                      exit 2
                    fi
                    CI_SCOPE_GATES="$gates_root" exec "$gates_root/scripts/check" "$@"
                    """
            ),
            AutomationScriptFile(
                id: "manifest", destinationPath: ".ci-scope.json", isExecutable: false,
                contents: "{{profile_manifest}}\n"
            ),
            AutomationScriptFile(
                id: "claude-hooks", destinationPath: ".claude/settings.json", isExecutable: false,
                contents: """
                    {
                      "hooks": {
                        "PostToolUse": [{"matcher": "Write|Edit|MultiEdit", "hooks": [{"type": "command", "command": "output=$(scripts/check 2>&1); status=$?; if [ \\"$status\\" -ne 0 ]; then printf '%s\\n' \\"$output\\" >&2; exit 2; fi # ci-scope-agent-toolkit"}]}],
                        "Stop": [{"hooks": [{"type": "command", "command": "if cat | grep -Eq '\\"stop_hook_active\\": *true'; then exit 0; fi; output=$(scripts/check 2>&1); status=$?; if [ \\"$status\\" -ne 0 ]; then printf '%s\\n' \\"$output\\" >&2; exit 2; fi # ci-scope-agent-toolkit"}]}]
                      }
                    }
                    """
            ),
            AutomationScriptFile(
                id: "agents", destinationPath: "AGENTS.md", isExecutable: false,
                contents: """
                    <!-- >>> ci-scope agent toolkit >>> -->
                    Run `scripts/check` before handing off changes.
                    <!-- <<< ci-scope agent toolkit <<< -->
                    """
            ),
        ]
    }

    static func agentToolkitManifest(_ profile: String) -> String {
        let stackChecks: [[String: Any]]
        switch profile {
        case "go":
            stackChecks = [["id": "go-quality", "type": "go-quality"]]
        case "python":
            stackChecks = [
                ["id": "python-quality", "type": "python-quality"],
                ["id": "python-tests", "type": "python-pytest"],
            ]
        case "swift":
            stackChecks = [
                ["id": "swift-quality", "type": "swift-quality", "params": ["run_build": false]],
                ["id": "swift-compile", "type": "swift-compile", "speed": "full"],
            ]
        case "unity":
            stackChecks = []  // no Unity check type in ci-gates yet; the shape gates below still apply
        default:
            stackChecks = [
                ["id": "web-quality", "type": "web-quality"],
                ["id": "web-tests", "type": "web-test"],
            ]
        }
        let checks =
            [["id": "code-linter", "type": "code-linter", "params": ["mode": "auto"]]]
            + stackChecks
            + [
                ["id": "forbidden-constructs", "type": "forbidden-constructs", "params": ["mode": "new"]],
                ["id": "duplicate-blocks", "type": "duplicate-blocks", "params": ["mode": "new"]],
                ["id": "file-roles", "type": "file-roles", "params": ["mode": "new"]],
                ["id": "agent-docs-stable", "type": "agent-docs-stable", "params": ["mode": "new"]],
            ]
        let object: [String: Any] = ["version": 1, "checks": checks]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}
