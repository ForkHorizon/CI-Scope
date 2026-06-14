# Graph Report - CI Scope  (2026-06-13)

## Corpus Check
- 87 files · ~77,926 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 1272 nodes · 2317 edges · 83 communities (78 shown, 5 thin omitted)
- Extraction: 98% EXTRACTED · 2% INFERRED · 0% AMBIGUOUS · INFERRED: 42 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `be9c04db`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- [[_COMMUNITY_Automation Script Installation|Automation Script Installation]]
- [[_COMMUNITY_Webhook & Delivery Codable Models|Webhook & Delivery Codable Models]]
- [[_COMMUNITY_Swift-Format Configuration|Swift-Format Configuration]]
- [[_COMMUNITY_Automation Script Errors|Automation Script Errors]]
- [[_COMMUNITY_Project CI Service & Config|Project CI Service & Config]]
- [[_COMMUNITY_Build & Warning Annotation (Python)|Build & Warning Annotation (Python)]]
- [[_COMMUNITY_Swift Path Discovery & Linting (Python)|Swift Path Discovery & Linting (Python)]]
- [[_COMMUNITY_Automation Script Store|Automation Script Store]]
- [[_COMMUNITY_Local Broker Service & Errors|Local Broker Service & Errors]]
- [[_COMMUNITY_Broker State Models|Broker State Models]]
- [[_COMMUNITY_Job Arrival Notifications|Job Arrival Notifications]]
- [[_COMMUNITY_Broker State Monitor|Broker State Monitor]]
- [[_COMMUNITY_Function-Length Linter (Python)|Function-Length Linter (Python)]]
- [[_COMMUNITY_Scripts View & Editor|Scripts View & Editor]]
- [[_COMMUNITY_Project CI Runner Loading|Project CI Runner Loading]]
- [[_COMMUNITY_Broker Managed Repos & Registry|Broker Managed Repos & Registry]]
- [[_COMMUNITY_Runner Fleet Service|Runner Fleet Service]]
- [[_COMMUNITY_Workflow Job Codable Models|Workflow Job Codable Models]]
- [[_COMMUNITY_Automation Script Install Flow|Automation Script Install Flow]]
- [[_COMMUNITY_ContentView & Workspace Tabs|ContentView & Workspace Tabs]]
- [[_COMMUNITY_Automation Script Models|Automation Script Models]]
- [[_COMMUNITY_Automation Script Validation|Automation Script Validation]]
- [[_COMMUNITY_GitHub Actions Runner Config|GitHub Actions Runner Config]]
- [[_COMMUNITY_GitHub Run Codable Models|GitHub Run Codable Models]]
- [[_COMMUNITY_README  Documentation|README / Documentation]]
- [[_COMMUNITY_Project CI Snapshot & Status|Project CI Snapshot & Status]]
- [[_COMMUNITY_Project CI Panel UI|Project CI Panel UI]]
- [[_COMMUNITY_Runner Setup Script (Python)|Runner Setup Script (Python)]]
- [[_COMMUNITY_Install Mode & Workspace Enums|Install Mode & Workspace Enums]]
- [[_COMMUNITY_Runner Fleet Loading|Runner Fleet Loading]]
- [[_COMMUNITY_Installed Scripts & Snapshots|Installed Scripts & Snapshots]]
- [[_COMMUNITY_Automation Script Storage|Automation Script Storage]]
- [[_COMMUNITY_Job Notification Banner UI|Job Notification Banner UI]]
- [[_COMMUNITY_Automation Script Seeds (PR templates)|Automation Script Seeds (PR templates)]]
- [[_COMMUNITY_Automation Script Seeds (PR templates)|Automation Script Seeds (PR templates)]]
- [[_COMMUNITY_Automation Script Seeds (PR templates)|Automation Script Seeds (PR templates)]]
- [[_COMMUNITY_Project Dashboard UI|Project Dashboard UI]]
- [[_COMMUNITY_Runners View UI|Runners View UI]]
- [[_COMMUNITY_Script Install Panel UI|Script Install Panel UI]]
- [[_COMMUNITY_Build  Warning Config Keys|Build / Warning Config Keys]]
- [[_COMMUNITY_Script Editor Form Fields|Script Editor Form Fields]]
- [[_COMMUNITY_Automation Script Renderer|Automation Script Renderer]]
- [[_COMMUNITY_Automation Script Seed Provider|Automation Script Seed Provider]]
- [[_COMMUNITY_Runner Work Strips UI|Runner Work Strips UI]]
- [[_COMMUNITY_Workflow Run Context|Workflow Run Context]]
- [[_COMMUNITY_Shared UI Components|Shared UI Components]]
- [[_COMMUNITY_Shell Client|Shell Client]]
- [[_COMMUNITY_Dead-Code  Periphery Config|Dead-Code / Periphery Config]]
- [[_COMMUNITY_Project Menu Panel UI|Project Menu Panel UI]]
- [[_COMMUNITY_Script Installer & Broker Access|Script Installer & Broker Access]]
- [[_COMMUNITY_Runner Work Items|Runner Work Items]]
- [[_COMMUNITY_Runner Webhook  Status Strips|Runner Webhook / Status Strips]]
- [[_COMMUNITY_Script List Row UI|Script List Row UI]]
- [[_COMMUNITY_Actions Runner Scope|Actions Runner Scope]]
- [[_COMMUNITY_Script Variable Kinds|Script Variable Kinds]]
- [[_COMMUNITY_Project Context Menu UI|Project Context Menu UI]]
- [[_COMMUNITY_Script Variables Editor UI|Script Variables Editor UI]]
- [[_COMMUNITY_Script Removal UI|Script Removal UI]]
- [[_COMMUNITY_Runner Sub-Runner Metrics UI|Runner Sub-Runner Metrics UI]]
- [[_COMMUNITY_Script Install Submenu UI|Script Install Submenu UI]]
- [[_COMMUNITY_Automation Script Naming|Automation Script Naming]]
- [[_COMMUNITY_Run Row UI|Run Row UI]]
- [[_COMMUNITY_Script Files Editor UI|Script Files Editor UI]]
- [[_COMMUNITY_Security Hardening Log|Security Hardening Log]]
- [[_COMMUNITY_Runner Label Codable Model|Runner Label Codable Model]]
- [[_COMMUNITY_Script Library UI|Script Library UI]]
- [[_COMMUNITY_Line-Count Linter Config|Line-Count Linter Config]]
- [[_COMMUNITY_Color Asset Metadata|Color Asset Metadata]]
- [[_COMMUNITY_Image Asset Metadata|Image Asset Metadata]]
- [[_COMMUNITY_App Entry Point|App Entry Point]]
- [[_COMMUNITY_Asset Catalog Metadata|Asset Catalog Metadata]]
- [[_COMMUNITY_Shell Quoting|Shell Quoting]]
- [[_COMMUNITY_Claude Settings (permissions)|Claude Settings (permissions)]]
- [[_COMMUNITY_Periphery Baseline|Periphery Baseline]]
- [[_COMMUNITY_Community 74|Community 74]]
- [[_COMMUNITY_Community 75|Community 75]]
- [[_COMMUNITY_Community 76|Community 76]]
- [[_COMMUNITY_Community 77|Community 77]]
- [[_COMMUNITY_Community 78|Community 78]]
- [[_COMMUNITY_Community 79|Community 79]]
- [[_COMMUNITY_Community 80|Community 80]]
- [[_COMMUNITY_Community 81|Community 81]]
- [[_COMMUNITY_Community 82|Community 82]]

## God Nodes (most connected - your core abstractions)
1. `View` - 59 edges
2. `AutomationScriptStore` - 30 edges
3. `rules` - 29 edges
4. `CodingKeys` - 23 edges
5. `ScriptsView` - 22 edges
6. `AutomationScriptInstaller` - 21 edges
7. `CodingKeys` - 21 edges
8. `BrokerStateMonitor` - 19 edges
9. `ContentView` - 18 edges
10. `LocalBrokerService` - 17 edges

## Surprising Connections (you probably didn't know these)
- `RunnerEmptyState` --references--> `View`  [EXTRACTED]
  CI Scope/RunnerWorkStrips.swift → CI Scope/ContentView+Layout.swift
- `RunRow` --references--> `View`  [EXTRACTED]
  CI Scope/CompactPanels.swift → CI Scope/ContentView+Layout.swift
- `ContentView` --references--> `View`  [EXTRACTED]
  CI Scope/ContentView.swift → CI Scope/ContentView+Layout.swift
- `JobNotificationBanner` --references--> `View`  [EXTRACTED]
  CI Scope/JobNotificationBanner.swift → CI Scope/ContentView+Layout.swift
- `JobNotificationJobRow` --references--> `View`  [EXTRACTED]
  CI Scope/JobNotificationBanner.swift → CI Scope/ContentView+Layout.swift

## Import Cycles
- None detected.

## Communities (83 total, 5 thin omitted)

### Community 0 - "Automation Script Installation"
Cohesion: 0.10
Nodes (25): AutomationScriptInstaller, AutomationScriptInstaller, AutomationScript, AutomationScriptInstallResult, AutomationScriptRenderer, CIProject, String, URL (+17 more)

### Community 1 - "Webhook & Delivery Codable Models"
Cohesion: 0.11
Nodes (19): CodingKeys, createdAt, enabled, htmlURL, id, labels, lastAction, lastDeliveryAt (+11 more)

### Community 2 - "Swift-Format Configuration"
Cohesion: 0.05
Nodes (42): fileScopedDeclarationPrivacy, accessLevel, indentation, spaces, indentBlankLines, indentConditionalCompilationBlocks, indentSwitchCaseLabels, lineLength (+34 more)

### Community 3 - "Automation Script Errors"
Cohesion: 0.08
Nodes (26): AutomationScriptError, commandFailed, duplicateScript, invalidDefaultBranch, invalidValue, missingProject, missingSeed, storage (+18 more)

### Community 4 - "Project CI Service & Config"
Cohesion: 0.08
Nodes (19): text, ProjectCIService, CIProject, Int, String, ProjectCIService, CIProject, DashboardConfig (+11 more)

### Community 5 - "Build & Warning Annotation (Python)"
Cohesion: 0.16
Nodes (37): Pattern, annotate_critical_warnings(), as_string_list(), build_command(), BuildResult, compile_patterns(), detect_project(), detect_scheme() (+29 more)

### Community 6 - "Swift Path Discovery & Linting (Python)"
Cohesion: 0.20
Nodes (33): all_repo_paths(), changed_paths(), collect_swift_paths(), detect_project(), detect_scheme(), ensure_periphery(), error(), escape_github_message() (+25 more)

### Community 7 - "Automation Script Store"
Cohesion: 0.18
Nodes (8): AutomationScriptStore, AutomationScript, Bool, Set, String, URL, FileManager, JSONEncoder

### Community 8 - "Local Broker Service & Errors"
Cohesion: 0.11
Nodes (16): LocalBrokerError, invalidRepository, launchAgent, missingResource, LocalBrokerService, ActionsRunnerConfig, Bool, String (+8 more)

### Community 9 - "Broker State Models"
Cohesion: 0.16
Nodes (15): LocalBrokerService, String, Bool, BrokerJob, BrokerRegistry, BrokerRepoStatus, BrokerRunnerProfile, BrokerState (+7 more)

### Community 10 - "Job Arrival Notifications"
Cohesion: 0.17
Nodes (9): NotificationManager, GitHubRun, JobArrivalNotification, RunnerFleetSnapshot, RunnerMonitorSnapshot, RunnerWorkItem, ServiceState, Set (+1 more)

### Community 11 - "Broker State Monitor"
Cohesion: 0.09
Nodes (17): BrokerStateMonitor, ProjectCIViewModel, CIProject, ProjectCISnapshot, BrokerStateMonitor, RunnerFleetViewModel, Bool, String (+9 more)

### Community 12 - "Function-Length Linter (Python)"
Cohesion: 0.20
Nodes (28): all_repo_paths(), brace_function_lengths(), changed_paths(), check_paths(), collect_paths(), detect_brace_function(), escape_github_message(), function_lengths() (+20 more)

### Community 13 - "Scripts View & Editor"
Cohesion: 0.14
Nodes (14): AutomationScriptInstallViewModel, AutomationScriptStore, ScriptEditorSection, details, files, variables, ScriptsView, AutomationScript (+6 more)

### Community 14 - "Project CI Runner Loading"
Cohesion: 0.22
Nodes (10): ProjectCIService, ActionsRunnerConfig, Bool, CIProject, GitHubActionsRunner, LoadResponse, ShellResult, String (+2 more)

### Community 15 - "Broker Managed Repos & Registry"
Cohesion: 0.14
Nodes (23): BrokerManagedRepo, BrokerJob, BrokerManagedRepo, BrokerRegistry, BrokerRepoStatus, BrokerRunnerProfile, BrokerRunnerProfileKind, organization (+15 more)

### Community 16 - "Runner Fleet Service"
Cohesion: 0.18
Nodes (9): RunnerFleetService, ActionsRunnerConfig, Bool, FleetGitHubActionsRunner, FleetLocalRunnerInfo, Int, RunnerLaunchStatus, String (+1 more)

### Community 17 - "Workflow Job Codable Models"
Cohesion: 0.10
Nodes (21): CodingKeys, createdAt, headBranch, id, jobId, jobName, labels, lastCheckedAt (+13 more)

### Community 18 - "Automation Script Install Flow"
Cohesion: 0.24
Nodes (9): AutomationScriptInstaller, AutomationScriptInstallViewModel, AutomationScript, AutomationScriptInstallMode, AutomationScriptInstallSnapshot, CIProject, DashboardConfig, String (+1 more)

### Community 19 - "ContentView & Workspace Tabs"
Cohesion: 0.17
Nodes (7): ContentView, Bool, CIProject, Date, ServiceState, String, WorkspaceTab

### Community 20 - "Automation Script Models"
Cohesion: 0.17
Nodes (9): AutomationScript, AutomationScriptFile, AutomationScriptInstallResult, AutomationScriptInstallSnapshot, AutomationScriptVariable, AutomationScriptInstallResult, Bool, ServiceState (+1 more)

### Community 21 - "Automation Script Validation"
Cohesion: 0.24
Nodes (7): AutomationScriptValidator, String, AutomationScript, AutomationScriptFile, AutomationScriptVariable, Bool, String

### Community 22 - "GitHub Actions Runner Config"
Cohesion: 0.18
Nodes (14): GitHubActionsRunner, GitHubAuthSnapshot, GitHubRunnerList, LoadResponse, LocalRunnerInfo, RunnerConfiguration, Substring, ActionsRunnerConfig (+6 more)

### Community 23 - "GitHub Run Codable Models"
Cohesion: 0.22
Nodes (9): CodingKeys, conclusion, createdAt, displayTitle, headBranch, htmlURL, id, name (+1 more)

### Community 24 - "README / Documentation"
Cohesion: 0.12
Nodes (16): Architecture, Automation Scripts, Build, CI Scope, Current Limitations, Intended Audience, Job Notifications, License (+8 more)

### Community 25 - "Project CI Snapshot & Status"
Cohesion: 0.19
Nodes (13): GitHubRun, GitHubWorkflow, ProjectCISnapshot, ProjectLocalRunnerStatus, ServiceState, offline, online, unknown (+5 more)

### Community 26 - "Project CI Panel UI"
Cohesion: 0.12
Nodes (13): ProjectCIPanel, String, AutomationScript, AutomationScriptInstallSnapshot, Bool, CIProject, GitHubWorkflow, GridItem (+5 more)

### Community 27 - "Runner Setup Script (Python)"
Cohesion: 0.27
Nodes (13): configure_org_runner(), configure_personal_runner(), configure_service(), ensure_runner_package(), fail(), main(), registration_token(), remove_existing_config() (+5 more)

### Community 28 - "Install Mode & Workspace Enums"
Cohesion: 0.16
Nodes (12): CaseIterable, AutomationScript, AutomationScriptInstallMode, githubHosted, localBroker, AutomationScript, Bool, WorkspaceTab (+4 more)

### Community 29 - "Runner Fleet Loading"
Cohesion: 0.26
Nodes (8): RunnerFleetService, String, ActionsRunnerConfig, DashboardConfig, FleetGitHubActionsRunner, FleetLoadResponse, RunnerMonitorSnapshot, ServiceState

### Community 30 - "Installed Scripts & Snapshots"
Cohesion: 0.21
Nodes (10): AutomationScript, InstalledAutomationScript, String, AutomationScript, Bool, GitHubWorkflow, ProjectCISnapshot, ServiceState (+2 more)

### Community 31 - "Automation Script Storage"
Cohesion: 0.25
Nodes (7): AutomationScript, AutomationScriptStore, String, AutomationScript, AutomationScriptFile, Set, String

### Community 32 - "Job Notification Banner UI"
Cohesion: 0.19
Nodes (13): JobNotificationBanner, JobNotificationJobRow, JobNotificationOverlay, JobNotificationPrimaryLine, JobNotificationSection, Bool, Color, Int (+5 more)

### Community 33 - "Automation Script Seeds (PR templates)"
Cohesion: 0.15
Nodes (12): branchName, commitMessage, defaultSeedID, detail, files, id, pullRequestBody, pullRequestTitle (+4 more)

### Community 34 - "Automation Script Seeds (PR templates)"
Cohesion: 0.15
Nodes (12): branchName, commitMessage, defaultSeedID, detail, files, id, pullRequestBody, pullRequestTitle (+4 more)

### Community 35 - "Automation Script Seeds (PR templates)"
Cohesion: 0.15
Nodes (12): branchName, commitMessage, defaultSeedID, detail, files, id, pullRequestBody, pullRequestTitle (+4 more)

### Community 36 - "Project Dashboard UI"
Cohesion: 0.19
Nodes (11): AddProjectSheet, EmptyProjectDashboard, ErrorBox, LimitedStatusRow, ProjectRunList, ProjectWorkflowList, GitHubRun, GitHubWorkflow (+3 more)

### Community 37 - "Runners View UI"
Cohesion: 0.19
Nodes (12): RunnerCard, RunnerFleetSummary, RunnerSummaryTile, RunnersView, Bool, Color, GridItem, RunnerFleetSnapshot (+4 more)

### Community 38 - "Script Install Panel UI"
Cohesion: 0.19
Nodes (12): AutomationScriptInstallStatusBox, ScriptInstallPanel, ScriptInstallVariableInput, AutomationScript, AutomationScriptInstallMode, AutomationScriptInstallSnapshot, AutomationScriptVariable, Binding (+4 more)

### Community 39 - "Build / Warning Config Keys"
Cohesion: 0.15
Nodes (12): critical_warning_exclude_patterns, critical_warning_patterns, fail_on_any_warning, ignore, swift_build_arguments, xcode_code_signing_allowed, xcode_configuration, xcode_destination (+4 more)

### Community 40 - "Script Editor Form Fields"
Cohesion: 0.24
Nodes (10): CGFloat, LabeledTextEditor, LabeledTextField, ScriptDetailsEditor, ScriptEditorPanel, AutomationScript, Binding, ScriptEditorSection (+2 more)

### Community 41 - "Automation Script Renderer"
Cohesion: 0.29
Nodes (5): AutomationScriptRenderer, AutomationScript, AutomationScriptFile, CIProject, String

### Community 42 - "Automation Script Seed Provider"
Cohesion: 0.35
Nodes (5): AutomationScriptSeedProvider, AutomationScript, AutomationScriptFile, AutomationScriptVariable, String

### Community 43 - "Runner Work Strips UI"
Cohesion: 0.36
Nodes (11): View, RunnerIcon, RunnerLabelStrip, RunnerStatePill, RunnerWarningLine, RunnerWorkEmptyRow, RunnerWorkRow, RunnerWorkSection (+3 more)

### Community 44 - "Workflow Run Context"
Cohesion: 0.38
Nodes (5): RunnerFleetService, ActionsRunnerConfig, FleetGitHubActionsRunner, FleetLoadResponse, FleetLocalRunnerInfo

### Community 45 - "Shared UI Components"
Cohesion: 0.21
Nodes (10): EmptyState, FileOpenButton, LogScroll, PanelShell, StatusDot, Bool, Color, ServiceState (+2 more)

### Community 46 - "Shell Client"
Cohesion: 0.32
Nodes (7): ShellClient, ShellResult, DashboardConfig, String, TimeInterval, Int32, Process

### Community 47 - "Dead-Code / Periphery Config"
Cohesion: 0.17
Nodes (11): dead_code_enabled, dead_code_install_periphery, fallback_swift_format_config, ignore, periphery_arguments, swift_format_config, xcode_configuration, xcode_destination (+3 more)

### Community 48 - "Project Menu Panel UI"
Cohesion: 0.27
Nodes (10): ProjectMenuPanel, Bool, CIProject, Color, Int, ServiceState, String, Void (+2 more)

### Community 49 - "Script Installer & Broker Access"
Cohesion: 0.31
Nodes (6): AutomationScriptInstaller, BrokerRepositoryAccess, AutomationScript, AutomationScriptInstallMode, CIProject, String

### Community 50 - "Runner Work Items"
Cohesion: 0.36
Nodes (6): FleetLocalRunnerInfo, Int, RunnerWorkItem, String, WorkflowJob, WorkflowRunContext

### Community 51 - "Runner Webhook / Status Strips"
Cohesion: 0.24
Nodes (8): color(), RunnerEmptyState, RunnerErrorStrip, RunnerWebhookStrip, BrokerWebhookStatus, Color, ServiceState, String

### Community 52 - "Script List Row UI"
Cohesion: 0.20
Nodes (9): ScriptListRow, AutomationScript, AutomationScriptInstallMode, AutomationScriptInstallSnapshot, Bool, CIProject, Color, String (+1 more)

### Community 53 - "Actions Runner Scope"
Cohesion: 0.31
Nodes (8): ActionsRunnerScope, ActionsRunnerConfig, ActionsRunnerScope, organization, personalAccount, repository, DashboardConfig, String

### Community 54 - "Script Variable Kinds"
Cohesion: 0.40
Nodes (5): AutomationScriptVariableKind, boolean, multiline, number, option

### Community 55 - "Project Context Menu UI"
Cohesion: 0.28
Nodes (8): ProjectContextMenu, ProjectMenuRow, Bool, CIProject, Color, ServiceState, String, Void

### Community 56 - "Script Variables Editor UI"
Cohesion: 0.25
Nodes (7): ScriptVariableCard, ScriptVariablesEditor, AutomationScript, AutomationScriptVariable, Binding, String, Void

### Community 57 - "Script Removal UI"
Cohesion: 0.36
Nodes (7): ProjectScriptRemovalList, ProjectScriptRemovalRow, AutomationScript, AutomationScriptInstallSnapshot, InstalledAutomationScript, ServiceState, Void

### Community 58 - "Runner Sub-Runner Metrics UI"
Cohesion: 0.36
Nodes (7): RunnerMetric, RunnerMiniMetric, RunnerSubRunnerDisclosure, RunnerSubRunnerRow, RunnerSubRunnerSnapshot, ServiceState, String

### Community 59 - "Script Install Submenu UI"
Cohesion: 0.25
Nodes (7): ScriptInstallSubmenu, AutomationScript, AutomationScriptInstallMode, AutomationScriptInstallSnapshot, CIProject, String, Void

### Community 60 - "Automation Script Naming"
Cohesion: 0.33
Nodes (5): AutomationScript, AutomationScriptNaming, Bool, String, UnicodeScalar

### Community 61 - "Run Row UI"
Cohesion: 0.29
Nodes (5): RunRow, Color, GitHubRun, ServiceState, String

### Community 62 - "Script Files Editor UI"
Cohesion: 0.33
Nodes (5): ScriptFileCard, ScriptFilesEditor, AutomationScript, AutomationScriptFile, Void

### Community 63 - "Security Hardening Log"
Cohesion: 0.29
Nodes (6): 2024-05-18 - [Add strict validation to repository URL inputs], 2024-05-24 - Validate System Command Input, 2024-06-04 - Safely Append URL Path Components, 2025-02-12 - Prevent Command Injection via String Interpolation, 2025-02-12 - Secure Info.plist by Enforcing ATS, 2025-02-14 - Prevent Terminal Injection

### Community 64 - "Runner Label Codable Model"
Cohesion: 0.33
Nodes (6): CodingKeys, id, name, path, state, CodingKey

### Community 65 - "Script Library UI"
Cohesion: 0.53
Nodes (5): ScriptLibraryList, ScriptLibraryRow, AutomationScript, Bool, Void

### Community 66 - "Line-Count Linter Config"
Cohesion: 0.33
Nodes (5): ignore, include_extensions, language_overrides, max_file_lines, max_function_lines

### Community 67 - "Color Asset Metadata"
Cohesion: 0.22
Nodes (8): colors, info, author, version, images, info, version, author

### Community 68 - "Image Asset Metadata"
Cohesion: 0.21
Nodes (15): BrokerWebhookStatus, FleetGitHubActionsRunner, FleetLoadResponse, FleetLocalRunnerInfo, FleetRunnerConfiguration, JobContext, RunnerWorkItem, ActionsRunnerConfig (+7 more)

### Community 69 - "App Entry Point"
Cohesion: 0.50
Nodes (3): App, CI_ScopeApp, Scene

### Community 70 - "Asset Catalog Metadata"
Cohesion: 0.31
Nodes (6): GitHubRateLimitGate, Bool, DashboardConfig, Date, ShellResult, String

### Community 74 - "Community 74"
Cohesion: 0.22
Nodes (12): GitHubRunnerLabel, FleetGitHubRunnerLabel, FleetGitHubRunnerList, FleetGitHubActionsRunner, Job, Run, Int, String (+4 more)

### Community 75 - "Community 75"
Cohesion: 0.20
Nodes (8): mapConcurrently(), Int, workflowRuns, JobContext, WorkflowRunContext, escaping, Item, Sendable

### Community 76 - "Community 76"
Cohesion: 0.36
Nodes (5): Bool, Int64, JobContext, WorkflowRunContext, WorkflowJobsCache

### Community 77 - "Community 77"
Cohesion: 0.31
Nodes (9): RunnerFleetSnapshot, RunnerLaunchStatus, RunnerMonitorSnapshot, RunnerSubRunnerSnapshot, BrokerWebhookStatus, Int, RunnerMonitorSnapshot, RunnerSubRunnerSnapshot (+1 more)

### Community 78 - "Community 78"
Cohesion: 0.25
Nodes (7): Int64, String, WorkflowJob, WorkflowJobList, WorkflowRun, WorkflowRunList, WorkflowRun

### Community 79 - "Community 79"
Cohesion: 0.36
Nodes (5): LocalBrokerService, Bool, GitHubRun, TimeInterval, WorkflowRunsFeed.Run

### Community 80 - "Community 80"
Cohesion: 0.83
Nodes (3): JobArrivalNotification, Date, RunnerWorkItem

## Knowledge Gaps
- **417 isolated node(s):** `commandFailed`, `duplicateScript`, `invalidDefaultBranch`, `invalidValue`, `missingProject` (+412 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **5 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `View` connect `Runner Work Strips UI` to `Scripts View & Editor`, `ContentView & Workspace Tabs`, `Project CI Panel UI`, `Job Notification Banner UI`, `Project Dashboard UI`, `Runners View UI`, `Script Install Panel UI`, `Script Editor Form Fields`, `Shared UI Components`, `Project Menu Panel UI`, `Runner Webhook / Status Strips`, `Script List Row UI`, `Project Context Menu UI`, `Script Variables Editor UI`, `Script Removal UI`, `Runner Sub-Runner Metrics UI`, `Script Install Submenu UI`, `Run Row UI`, `Script Files Editor UI`, `Script Library UI`?**
  _High betweenness centrality (0.209) - this node is a cross-community bridge._
- **Why does `ScriptEditorSection` connect `Scripts View & Editor` to `Project CI Snapshot & Status`, `Install Mode & Workspace Enums`?**
  _High betweenness centrality (0.202) - this node is a cross-community bridge._
- **Why does `ScriptsView` connect `Scripts View & Editor` to `Runner Work Strips UI`?**
  _High betweenness centrality (0.201) - this node is a cross-community bridge._
- **What connects `commandFailed`, `duplicateScript`, `invalidDefaultBranch` to the rest of the system?**
  _417 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Automation Script Installation` be split into smaller, more focused modules?**
  _Cohesion score 0.09887005649717515 - nodes in this community are weakly interconnected._
- **Should `Webhook & Delivery Codable Models` be split into smaller, more focused modules?**
  _Cohesion score 0.10526315789473684 - nodes in this community are weakly interconnected._
- **Should `Swift-Format Configuration` be split into smaller, more focused modules?**
  _Cohesion score 0.046511627906976744 - nodes in this community are weakly interconnected._