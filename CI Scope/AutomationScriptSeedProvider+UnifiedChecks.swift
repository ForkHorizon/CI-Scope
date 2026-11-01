import Foundation

extension AutomationScriptSeedProvider {
    static func fallbackUnifiedChecksSeed() -> AutomationScript {
        AutomationScript(
            id: "ci-scope-unified-checks",
            title: "CI Scope Unified Checks (SOMA pilot)",
            summary: "Runs SOMA's six configured gates in one GitHub job.",
            detail: "Installs the SOMA pilot manifest and one workflow pinned to a reviewed ci-gates commit.",
            runnerLabels: ["self-hosted", "macOS", "ARM64", "ci-scope-unified"],
            branchName: "ci-scope/install-{{script_id}}",
            commitMessage: "Add {{script_title}}",
            pullRequestTitle: "Add {{script_title}}",
            pullRequestBody:
                "Adds the unified CI Scope manifest and one GitHub Actions job. The ci-gates checkout is pinned to {{gates_sha}}.",
            variables: [
                AutomationScriptVariable(
                    id: "gates_sha",
                    title: "Reviewed ci-gates SHA",
                    kind: .text,
                    isRequired: true,
                    defaultValue: "REPLACE_WITH_REVIEWED_GATES_SHA",
                    help: "Full 40-character commit SHA containing the unified executor.",
                    options: []
                )
            ],
            files: unifiedChecksFiles,
            defaultSeedID: "ci-scope-unified-checks"
        )
    }

    private static var unifiedChecksFiles: [AutomationScriptFile] {
        [
            AutomationScriptFile(
                id: "manifest",
                destinationPath: ".ci-scope.json",
                isExecutable: false,
                contents: unifiedChecksManifest
            ),
            AutomationScriptFile(
                id: "workflow",
                destinationPath: ".github/workflows/ci-scope-checks.yml",
                isExecutable: false,
                contents: unifiedChecksWorkflow
            ),
        ]
    }

    private static let unifiedChecksManifest = """
        {
          "version": 1,
          "checks": [
            {"id": "code-linter", "type": "code-linter", "config": ".code-linter.json", "params": {"mode": "auto"}},
            {"id": "python-quality", "type": "python-quality"},
            {"id": "go-quality", "type": "go-quality", "workdir": "Soma/go_scanner"},
            {"id": "swift-quality", "type": "swift-quality", "config": ".swift-quality-gate.json", "params": {"run_build": false}, "resources": ["xcode"]},
            {"id": "swift-compile", "type": "swift-compile", "config": ".swift-compile-gate.json", "resources": ["xcode"]}
          ]
        }

        """

    private static let unifiedChecksWorkflow = """
        name: CI Scope

        on:
          pull_request:
          merge_group:
            types: [checks_requested]
          workflow_dispatch:
          push:
            branches: [main, development]
          schedule:
            - cron: "0 5 * * 1"

        permissions:
          contents: read
          pull-requests: read

        concurrency:
          group: ci-scope-checks-${{ github.workflow }}-${{ github.ref }}
          cancel-in-progress: true

        jobs:
          checks:
            name: Checks
            runs-on: {{runner_labels_json}}
            env:
              CI_SCOPE_GATES_SHA: {{gates_sha}}
            steps:
              - name: Checkout candidate
                uses: actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803
                with:
                  path: candidate
                  fetch-depth: 0
                  persist-credentials: false

              - name: Checkout ci-gates
                uses: actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803
                with:
                  repository: ForkHorizon/ci-gates
                  ref: {{gates_sha}}
                  path: ci-gates
                  fetch-depth: 1
                  persist-credentials: false

              - name: Verify ci-gates pin
                shell: bash
                run: |
                  set -euo pipefail
                  [[ "$(git -C ci-gates rev-parse HEAD)" == "${CI_SCOPE_GATES_SHA:?}" ]]

              - name: Resolve revision range
                id: range
                working-directory: candidate
                shell: bash
                env:
                  EVENT_NAME: ${{ github.event_name }}
                  PR_BASE_SHA: ${{ github.event.pull_request.base.sha }}
                  PR_HEAD_SHA: ${{ github.event.pull_request.head.sha }}
                  MERGE_BASE_SHA: ${{ github.event.merge_group.base_sha }}
                  EVENT_SHA: ${{ github.sha }}
                run: |
                  set -euo pipefail
                  base="HEAD^"
                  head="$EVENT_SHA"
                  case "$EVENT_NAME" in
                    pull_request) base="$PR_BASE_SHA"; head="$PR_HEAD_SHA" ;;
                    merge_group) base="$MERGE_BASE_SHA" ;;
                  esac
                  echo "base=$base" >> "$GITHUB_OUTPUT"
                  echo "head=$head" >> "$GITHUB_OUTPUT"

              - name: Validate manifest
                run: |
                  python3 ci-gates/scripts/run-checks.py \
                    --root candidate \
                    --config candidate/.ci-scope.json \
                    --gates ci-gates \
                    --event "${{ github.event_name }}" \
                    --base "${{ steps.range.outputs.base }}" \
                    --head "${{ steps.range.outputs.head }}" \
                    --output "$RUNNER_TEMP/ci-scope" \
                    --validate-only

              - name: Select trusted policy
                id: policy
                working-directory: candidate
                shell: bash
                env:
                  EVENT_NAME: ${{ github.event_name }}
                  BASE_SHA: ${{ steps.range.outputs.base }}
                run: |
                  set -euo pipefail
                  config="$PWD/.ci-scope.json"
                  if [[ "$EVENT_NAME" == "pull_request" || "$EVENT_NAME" == "merge_group" ]]; then
                    config="$RUNNER_TEMP/ci-scope-base-policy.json"
                    git show "$BASE_SHA:.ci-scope.json" > "$config"
                  fi
                  echo "config=$config" >> "$GITHUB_OUTPUT"

              - name: Materialize trusted policy files
                if: ${{ github.event_name == 'pull_request' || github.event_name == 'merge_group' }}
                working-directory: candidate
                env:
                  BASE_SHA: ${{ steps.range.outputs.base }}
                run: |
                  set -euo pipefail
                  python3 - "$BASE_SHA" <<'PY'
                  import json
                  import pathlib
                  import subprocess
                  import sys
                  base = sys.argv[1]
                  manifest = json.loads(subprocess.check_output(["git", "show", f"{base}:.ci-scope.json"], text=True))
                  defaults = {"code-linter": ".code-linter.json", "swift-quality": ".swift-quality-gate.json", "swift-compile": ".swift-compile-gate.json", "slop-review": ".slop-review.json"}
                  root = pathlib.Path.cwd().resolve()
                  for check in manifest["checks"]:
                      explicit = "config" in check
                      path = check.get("config") or defaults.get(check.get("type"))
                      if not path:
                          continue
                      relative = pathlib.PurePosixPath(path)
                      if relative.is_absolute() or ".." in relative.parts:
                          raise SystemExit(f"unsafe policy path: {path}")
                      target = root / pathlib.Path(relative)
                      if target.resolve(strict=False) != target:
                          raise SystemExit(f"unsafe policy symlink: {path}")
                      try:
                          data = subprocess.check_output(["git", "show", f"{base}:{relative}"], stderr=subprocess.STDOUT)
                      except subprocess.CalledProcessError:
                          if explicit:
                              raise
                          continue
                      target.parent.mkdir(parents=True, exist_ok=True)
                      target.write_bytes(data)
                  PY

              - name: Run checks
                run: |
                  python3 ci-gates/scripts/run-checks.py \
                    --root candidate \
                    --config "${{ steps.policy.outputs.config }}" \
                    --gates ci-gates \
                    --event "${{ github.event_name }}" \
                    --base "${{ steps.range.outputs.base }}" \
                    --head "${{ steps.range.outputs.head }}" \
                    --output "$RUNNER_TEMP/ci-scope"

              - name: Publish summary
                if: always()
                shell: python3 {0}
                env:
                  REPORT: ${{ runner.temp }}/ci-scope/result.json
                run: |
                  import json, os
                  report_path = os.environ["REPORT"]
                  summary_path = os.environ["GITHUB_STEP_SUMMARY"]
                  try:
                      report = json.load(open(report_path, encoding="utf-8"))
                  except (OSError, ValueError):
                      open(summary_path, "a", encoding="utf-8").write("## CI Scope\n\nResults unavailable.\n")
                  else:
                      lines = ["## CI Scope / Checks", "", f"**Status:** {report.get('status', 'unknown')}", "", "| Check | Status | Duration |", "| --- | --- | ---: |"]
                      for check in report.get("checks", []):
                          lines.append(f"| `{check.get('id', '?')}` | {check.get('status', 'unknown')} | {check.get('duration_ms', 0)} ms |")
                      open(summary_path, "a", encoding="utf-8").write("\n".join(lines) + "\n")

              - name: Upload reports
                if: always()
                uses: actions/upload-artifact@v4
                with:
                  name: ci-scope-${{ github.run_id }}-${{ github.run_attempt }}
                  path: ${{ runner.temp }}/ci-scope
                  if-no-files-found: warn

        """
}
