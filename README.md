# CI Scope

CI Scope is a local macOS dashboard for watching GitHub Actions repositories, self-hosted runner health, and installable CI automation scripts.

It is built for situations where GitHub workflows run on a local Mac and the important state is split across GitHub, local runner registration, queued jobs, and reusable workflow templates. The app brings that state into one focused SwiftUI interface so a developer can see repository CI status, runner availability, and the scripts that can be installed into a project.

## Status

Personal/internal tool in active development. The source is public for reference and reuse, but local runner configuration is currently machine-specific and lives in `CI Scope/DashboardConfig.swift`.

APIs, project settings, and release packaging may change before a reusable public app release.

## What It Does

- Manages a local list of GitHub repositories.
- Loads GitHub Actions workflows and recent runs through the GitHub CLI.
- Detects which repository the configured local GitHub runner is registered to.
- Shows runner fleet status, runner labels, active work, and queued work.
- Manages installable automation scripts for CI workflows.
- Installs scripts into selected projects through generated pull requests.
- Shows repository status without treating any repository as special.
- Provides repository actions such as copying the SSH URL and opening GitHub.
- Supports right-click and ellipsis context menus for project actions, including removing projects.
- Shows a clean empty state when there are no saved projects.

## Project Model

Projects are normal saved repositories. No repository is protected, seeded, or treated as a primary project by the app.

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

## Automation Scripts

Scripts are reusable CI workflow templates. The Scripts workspace shows the script library as a list, expands the selected script inline for install options, and opens the editor in a sheet when a script needs to be changed.

Default scripts are bundled in:

```text
CI Scope/AutomationScriptSeeds
```

User-created or edited scripts are stored locally in Application Support:

```text
~/Library/Application Support/CI Scope/Scripts
```

Installing a script renders its files into the target repository, commits the changes on a branch, pushes that branch, and opens a pull request. The current install mode uses the local Mac runner broker so projects can target the configured self-hosted runner labels.

## Local Configuration

The local runner configuration is currently hardcoded in:

```text
CI Scope/DashboardConfig.swift
```

That file defines:

- GitHub runner roots and scopes.
- Required runner labels.
- Optional launch service labels.
- Shell `PATH` used when running local commands.

Future work should move this from one hardcoded config into per-project settings.

## Requirements

- macOS.
- Xcode with SwiftUI support.
- GitHub CLI installed and authenticated:

```bash
gh auth status -h github.com
```

- Git installed for workflow fallback detection.
- GitHub self-hosted runner configured on this Mac for runner and script-install workflows.

The app can still show repository and GitHub Actions information without an online local runner.

## Runner Model

CI Scope expects two local GitHub Actions runner scopes for normal use:

- One **organization runner** for `ForkHorizon` repositories.
- One **personal repo runner** for a selected `Daliys/<repo>` personal repository.

Both runners should run on this Mac and include these labels:

```text
self-hosted, macOS, ARM64, ci-scope
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

### Job Notifications

CI Scope shows job arrivals through an in-app Liquid Glass notification banner and also sends a native macOS notification when notification permission is available. The banner self-dismisses after five seconds and can be dismissed manually.

The MacBook Runner broker is designed to avoid GitHub polling in normal use.
The production path is a GitHub App backend:

```text
GitHub App webhook -> CI Scope backend -> outbound SSE -> local broker -> Swift UI
```

The backend lives in `backend/` and stores normalized GitHub webhook state in
SQLite. GitHub should call this backend directly; do not add per-workflow
`curl` steps for CI Scope events. Configure the GitHub App webhook URL to:

```text
https://ci.forkhorizon.com/github/webhook
```

Subscribe the GitHub App to:

- `workflow_job`
- `workflow_run`
- `push`
- `repository`
- `installation_repositories`

Start the local broker with:

```text
CI_SCOPE_BACKEND_URL=https://ci.forkhorizon.com
CI_SCOPE_BACKEND_TOKEN=<shared client token>
```

When the backend is healthy, CI Scope reads queue/run state from the backend on
startup, then uses SSE only as a wakeup signal to sync a fresh snapshot. If the
backend is down, the broker falls back to slow GitHub reconciliation polling
instead of the old tight loop.

Without `CI_SCOPE_BACKEND_URL`, the broker still supports a localhost-only
webhook path for ad-hoc setups:

```text
POST http://127.0.0.1:8765/github/workflow-job
```

GitHub cannot call a private localhost URL directly, so expose that local endpoint through a free HTTPS tunnel or relay when you want near-live webhook delivery. Configure a GitHub repository or organization webhook with:

- Event: `workflow_job`
- Content type: `application/json`
- Secret: the contents of `~/Library/Application Support/CI Scope/Broker/webhook-secret`

The webhook secret is generated automatically when CI Scope installs or updates the broker launch agent. If no webhook deliveries arrive, the broker uses a slow GitHub CLI reconciliation fallback; once webhooks are active, that fallback remains slow and only repairs missed deliveries.

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

## License

No open-source license has been declared yet. Until a license file is added, the public source should be treated as visible reference code rather than reusable licensed software.

## Architecture

- `ContentView.swift` contains the SwiftUI shell, sidebar, project details, context menus, empty states, and workspace routing.
- `ProjectStore.swift` owns saved repository data, selection, add/remove behavior, duplicate prevention, and git URL parsing.
- `ProjectCIService.swift` loads GitHub workflows/runs, GitHub auth diagnostics, and repo-aware local runner status.
- `ProjectCIViewModel.swift` caches per-project CI snapshots and invalidates removed projects.
- `RunnerFleetService.swift` loads runner fleet status, labels, active work, and queued work.
- `AutomationScriptStore.swift` owns the local script library and default script seeding.
- `AutomationScriptInstaller.swift` renders script files, commits changes, pushes branches, and creates pull requests.
- `LocalBrokerService.swift` manages the local runner broker registry and launch agent support.
- `DashboardConfig.swift` is the current single source of local runner configuration.
- `Models.swift` contains shared status and snapshot models.
- `ShellClient.swift` runs local shell commands with timeouts and configured environment.

The app has no backend service. It reads local files, runs local shell commands, and uses the GitHub CLI from the Mac where the app is running.

## Safety Notes

- Repository add/remove operations affect only local app state.
- GitHub Actions data is read through `gh`; CI Scope does not trigger remote workflow runs.
- Script installation writes files into the selected repository, commits them on a new branch, pushes that branch, and opens a pull request.
- GitHub CLI auth output is sanitized before being shown in error details.

## Current Limitations

- Local runner/config support is single-config, not per-project.
- New projects are not cloned automatically.
- GitHub Actions access depends on the current `gh` authentication and repository permissions.
- Workflow file detection falls back to a temporary sparse clone only when the GitHub CLI workflow API path fails.
- Script installation depends on local Git and GitHub CLI access to the target repository.

## Intended Audience

This repository is meant to be understandable by both human maintainers and AI coding agents.

When modifying it, preserve these product principles:

- Repositories are equal; do not reintroduce primary-project behavior.
- Keep local machine integrations explicit and configurable.
- Prefer clear empty states over raw errors when a repository has no Actions.
- Keep destructive actions local-only unless the UI explicitly says otherwise.
- Keep script install behavior explicit: generated changes should go through a branch and pull request.
