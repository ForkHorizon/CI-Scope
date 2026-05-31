# CI Scope

CI Scope is a local macOS dashboard for watching GitHub Actions repositories and the machine-side tools that support a self-hosted CI workflow.

It is built for situations where GitHub workflows run on a local Mac and the important state is split across GitHub, `launchctl`, runner logs, Ollama, Unity, and local validation scripts. The app brings that state into one focused SwiftUI interface so a developer can see whether a repository has Actions, whether a local runner is registered to it, what the latest runs look like, and what local tooling is available.

## What It Does

- Manages a local list of GitHub repositories.
- Loads GitHub Actions workflows and recent runs through the GitHub CLI.
- Detects which repository the configured local GitHub runner is registered to.
- Shows repository status without treating any repository as special.
- Provides repository actions such as copying the SSH URL and opening GitHub.
- Supports right-click and ellipsis context menus for project actions, including removing projects.
- Shows a clean empty state when there are no saved projects.
- Shows optional local tooling only when the selected repository matches the configured local runner setup.

For the currently configured local setup, CI Scope can also show:

- `launchctl` runner status, PID, and uptime.
- Runner stdout/stderr and latest runner/worker diagnostic logs.
- Ollama loaded models and available model tags.
- Unity/Nexus local server status through `get_server_status`.
- Parsed local validation stages from `validate.yml` and `prepush-validate.sh`.
- Buttons for local validation commands: static, quick, checklist AI, quality AI, and Unity smoke.

## Project Model

Projects are normal saved repositories. NexusUnity is not protected, seeded, or treated as a primary project by the app.

Project data is stored locally in `UserDefaults`:

- `ciScope.projects`
- `ciScope.selectedProjectID`

Adding a project accepts these formats:

```text
git@github.com:owner/repo.git
https://github.com/owner/repo.git
https://github.com/owner/repo
owner/repo
```

Removing a project deletes only the local saved entry. It does not delete files, clone repositories, unregister runners, or change anything on GitHub.

## Local Tooling Behavior

Every selected repository uses the same CI detail screen.

The extra local tools section appears only when the selected repository slug matches `DashboardConfig.repositorySlug`. In the current local configuration that points at `ForkHorizon/NexusUnity`, but that is only configuration data, not a special app rule.

The local configuration is currently hardcoded in:

```text
CI Scope/DashboardConfig.swift
```

That file defines:

- GitHub repository owner/name used for local tool matching.
- Local package/repository path.
- GitHub runner root and launch service label.
- Runner stdout/stderr log paths.
- Ollama base URL.
- Unity/Nexus JSON-RPC URL.
- Unity editor path.
- AI model used by local validation commands.
- Shell `PATH` used when launching local commands.

Future work should move this from one hardcoded config into per-project settings.

## Requirements

- macOS.
- Xcode with SwiftUI support.
- GitHub CLI installed and authenticated:

```bash
gh auth status -h github.com
```

- Git installed for workflow fallback detection.
- Optional local services for the full local-tools panel:
  - GitHub self-hosted runner configured on this Mac.
  - Ollama running on the configured URL.
  - Unity editor installed at the configured path.
  - Nexus/Unity local server running on the configured JSON-RPC endpoint.

The app can still show repository and GitHub Actions information without the optional local services.

## Runner Model

CI Scope expects two local GitHub Actions runner scopes for normal use:

- One **organization runner** for `ForkHorizon` repositories.
- One **personal repo runner** for a selected `Daliys/<repo>` personal repository.

Both runners should run on this Mac and include these labels:

```text
self-hosted, macOS, ARM64, ci-scope
```

The current Mac runner setup also preserves compatibility labels:

```text
ForkHorizon org runner: nexus-doc-ai, nexus-unity-ci
Daliys personal runner: moodling, ollama
```

The portable AI readability workflow targets those labels:

```yaml
runs-on: [self-hosted, macOS, ARM64, ci-scope]
```

One runner process handles one job at a time. If three jobs target the same organization runner, GitHub queues them and the Mac processes them one by one. If the organization runner and personal runner both receive work, they may run at the same time because they are separate runner processes.

GitHub does not support one personal-account runner shared across every personal repository. A personal repository needs a repository-level runner. CI Scope keeps one personal runner slot at:

```text
/Users/daliys/actions-runner/moodling
```

Re-run the personal setup command to point that slot at a different personal repo.

### Runner Setup

Refresh GitHub CLI scopes before configuring organization runners:

```bash
gh auth refresh -h github.com -s repo -s admin:org
```

Install or update the organization runner:

```bash
scripts/setup-ci-scope-runners.sh org ForkHorizon
```

Install or move the personal runner to one personal repo:

```bash
scripts/setup-ci-scope-runners.sh personal Daliys/MyPrivateRepo
```

After the organization runner is registered, check GitHub organization settings:

```text
ForkHorizon -> Settings -> Actions -> Runners -> Runner groups
```

Allow the runner group for the repositories that should use this Mac. Personal repo runners are configured in the repository settings:

```text
Repository -> Settings -> Actions -> Runners
```

## Build

Open the project in Xcode:

```bash
open "CI Scope.xcodeproj"
```

Or build from the command line:

```bash
xcodebuild \
  -project "CI Scope.xcodeproj" \
  -scheme "CI Scope" \
  -configuration Debug \
  -destination "platform=macOS" \
  build
```

## Architecture

- `ContentView.swift` contains the SwiftUI shell, sidebar, project details, context menus, empty states, local tool panels, and file-open controls.
- `ProjectStore.swift` owns saved repository data, selection, add/remove behavior, duplicate prevention, and git URL parsing.
- `ProjectCIService.swift` loads GitHub workflows/runs, GitHub auth diagnostics, and repo-aware local runner status.
- `ProjectCIViewModel.swift` caches per-project CI snapshots and invalidates removed projects.
- `DashboardService.swift` loads optional local tool snapshots: runner, Ollama, Unity server, logs, and parsed script stages.
- `LocalCommandRunner.swift` executes local validation command presets and streams output into the UI.
- `DashboardConfig.swift` is the current single source of local machine configuration.
- `Models.swift` contains shared status and snapshot models.
- `ShellClient.swift` runs local shell commands with timeouts and configured environment.

The app has no backend service. It reads local files, runs local shell commands, calls local HTTP endpoints, and uses the GitHub CLI from the Mac where the app is running.

## Safety Notes

- Repository add/remove operations affect only local app state.
- GitHub Actions data is read through `gh`; CI Scope does not trigger remote workflow runs.
- Local command buttons do execute shell commands from the configured repository root.
- File buttons reveal existing local log/script files in Finder.
- GitHub CLI auth output is sanitized before being shown in error details.

## Current Limitations

- Local runner/config support is single-config, not per-project.
- New projects are not cloned automatically.
- GitHub Actions access depends on the current `gh` authentication and repository permissions.
- Workflow file detection falls back to a temporary sparse clone only when the GitHub CLI workflow API path fails.
- The local Unity/Nexus status panel depends on the configured JSON-RPC server shape.

## Intended Audience

This repository is meant to be understandable by both human maintainers and AI coding agents.

When modifying it, preserve these product principles:

- Repositories are equal; do not reintroduce primary-project behavior.
- Keep local machine integrations explicit and configurable.
- Prefer clear empty states over raw errors when a repository has no Actions.
- Keep destructive actions local-only unless the UI explicitly says otherwise.
- Do not hide long-running local command output; the dashboard exists to make CI behavior visible.
