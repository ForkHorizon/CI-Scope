# Graph Report - .  (2026-06-13)

## Corpus Check
- 81 files · ~75,927 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 1227 nodes · 2237 edges · 74 communities (71 shown, 3 thin omitted)
- Extraction: 98% EXTRACTED · 2% INFERRED · 0% AMBIGUOUS · INFERRED: 39 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_Swift-Format Configuration|Swift-Format Configuration]]
- [[_COMMUNITY_Claude Settings (permissions)|Claude Settings (permissions)]]
- [[_COMMUNITY_Line-Count Linter Config|Line-Count Linter Config]]
- [[_COMMUNITY_Periphery Baseline|Periphery Baseline]]
- [[_COMMUNITY_Build  Warning Config Keys|Build / Warning Config Keys]]
- [[_COMMUNITY_Dead-Code  Periphery Config|Dead-Code / Periphery Config]]
- [[_COMMUNITY_Color Asset Metadata|Color Asset Metadata]]
- [[_COMMUNITY_Image Asset Metadata|Image Asset Metadata]]
- [[_COMMUNITY_Asset Catalog Metadata|Asset Catalog Metadata]]
- [[_COMMUNITY_Automation Script Errors|Automation Script Errors]]
- [[_COMMUNITY_Install Mode & Workspace Enums|Install Mode & Workspace Enums]]
- [[_COMMUNITY_Project CI Snapshot & Status|Project CI Snapshot & Status]]
- [[_COMMUNITY_Script Variable Kinds|Script Variable Kinds]]
- [[_COMMUNITY_Automation Script Install Flow|Automation Script Install Flow]]
- [[_COMMUNITY_Job Arrival Notifications|Job Arrival Notifications]]
- [[_COMMUNITY_Script Installer & Broker Access|Script Installer & Broker Access]]
- [[_COMMUNITY_Automation Script Installation|Automation Script Installation]]
- [[_COMMUNITY_Automation Script Models|Automation Script Models]]
- [[_COMMUNITY_Broker Managed Repos & Registry|Broker Managed Repos & Registry]]
- [[_COMMUNITY_Project CI Service & Config|Project CI Service & Config]]
- [[_COMMUNITY_Automation Script Naming|Automation Script Naming]]
- [[_COMMUNITY_Installed Scripts & Snapshots|Installed Scripts & Snapshots]]
- [[_COMMUNITY_Automation Script Renderer|Automation Script Renderer]]
- [[_COMMUNITY_Automation Script Seed Provider|Automation Script Seed Provider]]
- [[_COMMUNITY_Automation Script Seeds (PR templates)|Automation Script Seeds (PR templates)]]
- [[_COMMUNITY_Automation Script Seeds (PR templates)|Automation Script Seeds (PR templates)]]
- [[_COMMUNITY_Automation Script Seeds (PR templates)|Automation Script Seeds (PR templates)]]
- [[_COMMUNITY_Automation Script Storage|Automation Script Storage]]
- [[_COMMUNITY_Automation Script Store|Automation Script Store]]
- [[_COMMUNITY_Automation Script Validation|Automation Script Validation]]
- [[_COMMUNITY_App Entry Point|App Entry Point]]
- [[_COMMUNITY_Run Row UI|Run Row UI]]
- [[_COMMUNITY_ContentView & Workspace Tabs|ContentView & Workspace Tabs]]
- [[_COMMUNITY_Runner Work Strips UI|Runner Work Strips UI]]
- [[_COMMUNITY_Actions Runner Scope|Actions Runner Scope]]
- [[_COMMUNITY_Job Notification Banner UI|Job Notification Banner UI]]
- [[_COMMUNITY_Local Broker Service & Errors|Local Broker Service & Errors]]
- [[_COMMUNITY_Workflow Job Codable Models|Workflow Job Codable Models]]
- [[_COMMUNITY_Runner Label Codable Model|Runner Label Codable Model]]
- [[_COMMUNITY_Broker State Models|Broker State Models]]
- [[_COMMUNITY_GitHub Actions Runner Config|GitHub Actions Runner Config]]
- [[_COMMUNITY_Project CI Panel UI|Project CI Panel UI]]
- [[_COMMUNITY_Project CI Runner Loading|Project CI Runner Loading]]
- [[_COMMUNITY_Project Dashboard UI|Project Dashboard UI]]
- [[_COMMUNITY_Project Context Menu UI|Project Context Menu UI]]
- [[_COMMUNITY_Script Removal UI|Script Removal UI]]
- [[_COMMUNITY_Project Menu Panel UI|Project Menu Panel UI]]
- [[_COMMUNITY_GitHub Run Codable Models|GitHub Run Codable Models]]
- [[_COMMUNITY_Workflow Run Context|Workflow Run Context]]
- [[_COMMUNITY_Runner Fleet Service|Runner Fleet Service]]
- [[_COMMUNITY_Webhook & Delivery Codable Models|Webhook & Delivery Codable Models]]
- [[_COMMUNITY_Runner Fleet Loading|Runner Fleet Loading]]
- [[_COMMUNITY_Runner Work Items|Runner Work Items]]
- [[_COMMUNITY_Broker State Monitor|Broker State Monitor]]
- [[_COMMUNITY_Runner Sub-Runner Metrics UI|Runner Sub-Runner Metrics UI]]
- [[_COMMUNITY_Runner Webhook  Status Strips|Runner Webhook / Status Strips]]
- [[_COMMUNITY_Runners View UI|Runners View UI]]
- [[_COMMUNITY_Script Editor Form Fields|Script Editor Form Fields]]
- [[_COMMUNITY_Script Files Editor UI|Script Files Editor UI]]
- [[_COMMUNITY_Script Install Panel UI|Script Install Panel UI]]
- [[_COMMUNITY_Script Install Submenu UI|Script Install Submenu UI]]
- [[_COMMUNITY_Script Library UI|Script Library UI]]
- [[_COMMUNITY_Script List Row UI|Script List Row UI]]
- [[_COMMUNITY_Script Variables Editor UI|Script Variables Editor UI]]
- [[_COMMUNITY_Scripts View & Editor|Scripts View & Editor]]
- [[_COMMUNITY_Shared UI Components|Shared UI Components]]
- [[_COMMUNITY_Shell Client|Shell Client]]
- [[_COMMUNITY_Shell Quoting|Shell Quoting]]
- [[_COMMUNITY_Function-Length Linter (Python)|Function-Length Linter (Python)]]
- [[_COMMUNITY_Runner Setup Script (Python)|Runner Setup Script (Python)]]
- [[_COMMUNITY_Build & Warning Annotation (Python)|Build & Warning Annotation (Python)]]
- [[_COMMUNITY_Swift Path Discovery & Linting (Python)|Swift Path Discovery & Linting (Python)]]
- [[_COMMUNITY_Security Hardening Log|Security Hardening Log]]
- [[_COMMUNITY_README  Documentation|README / Documentation]]

## God Nodes (most connected - your core abstractions)
1. `View` - 59 edges
2. `AutomationScriptStore` - 30 edges
3. `rules` - 29 edges
4. `CodingKeys` - 23 edges
5. `ScriptsView` - 22 edges
6. `str` - 22 edges
7. `AutomationScriptInstaller` - 21 edges
8. `CodingKeys` - 21 edges
9. `BrokerStateMonitor` - 19 edges
10. `ContentView` - 18 edges

## Surprising Connections (you probably didn't know these)
- `View` --references--> `RunnerEmptyState`  [EXTRACTED]
  CI Scope/ContentView+Layout.swift → CI Scope/RunnerWorkStrips.swift
- `RunRow` --references--> `View`  [EXTRACTED]
  CI Scope/CompactPanels.swift → CI Scope/ContentView+Layout.swift
- `View` --references--> `ContentView`  [EXTRACTED]
  CI Scope/ContentView+Layout.swift → CI Scope/ContentView.swift
- `View` --references--> `JobNotificationBanner`  [EXTRACTED]
  CI Scope/ContentView+Layout.swift → CI Scope/JobNotificationBanner.swift
- `View` --references--> `JobNotificationJobRow`  [EXTRACTED]
  CI Scope/ContentView+Layout.swift → CI Scope/JobNotificationBanner.swift

## Import Cycles
- None detected.

## Communities (74 total, 3 thin omitted)

### Community 2 - "Swift-Format Configuration"
Cohesion: 0.05
Nodes (42): fileScopedDeclarationPrivacy, accessLevel, indentBlankLines, indentConditionalCompilationBlocks, indentSwitchCaseLabels, indentation, spaces, lineLength (+34 more)

### Community 66 - "Line-Count Linter Config"
Cohesion: 0.33
Nodes (5): max_file_lines, max_function_lines, include_extensions, ignore, language_overrides

### Community 39 - "Build / Warning Config Keys"
Cohesion: 0.15
Nodes (12): ignore, xcode_workspace, xcode_project, xcode_scheme, xcode_destination, xcode_configuration, xcode_code_signing_allowed, xcodebuild_arguments (+4 more)

### Community 47 - "Dead-Code / Periphery Config"
Cohesion: 0.17
Nodes (11): ignore, xcode_workspace, xcode_project, xcode_scheme, xcode_destination, xcode_configuration, swift_format_config, fallback_swift_format_config (+3 more)

### Community 67 - "Color Asset Metadata"
Cohesion: 0.40
Nodes (4): colors, info, author, version

### Community 68 - "Image Asset Metadata"
Cohesion: 0.40
Nodes (4): images, info, author, version

### Community 70 - "Asset Catalog Metadata"
Cohesion: 0.50
Nodes (3): info, author, version

### Community 3 - "Automation Script Errors"
Cohesion: 0.08
Nodes (26): AutomationScriptError, LocalizedError, commandFailed, duplicateScript, invalidDefaultBranch, invalidValue, missingProject, missingSeed (+18 more)

### Community 28 - "Install Mode & Workspace Enums"
Cohesion: 0.14
Nodes (11): AutomationScriptInstallMode, CaseIterable, localBroker, githubHosted, AutomationScript, AutomationScript, Bool, WorkspaceTab (+3 more)

### Community 25 - "Project CI Snapshot & Status"
Cohesion: 0.22
Nodes (14): String, Decodable, ServiceState, online, warning, offline, unknown, GitHubRun (+6 more)

### Community 54 - "Script Variable Kinds"
Cohesion: 0.22
Nodes (9): Identifiable, AutomationScriptVariableKind, multiline, boolean, number, option, BrokerJob, Int64 (+1 more)

### Community 18 - "Automation Script Install Flow"
Cohesion: 0.24
Nodes (9): AutomationScriptInstallViewModel, String, AutomationScriptInstallSnapshot, AutomationScriptInstaller, DashboardConfig, AutomationScript, CIProject, AutomationScriptInstallMode (+1 more)

### Community 10 - "Job Arrival Notifications"
Cohesion: 0.11
Nodes (14): ObservableObject, NotificationManager, JobArrivalNotification, String, ServiceState, Set, GitHubRun, RunnerFleetSnapshot (+6 more)

### Community 49 - "Script Installer & Broker Access"
Cohesion: 0.31
Nodes (6): AutomationScriptInstaller, AutomationScriptInstallMode, CIProject, AutomationScript, String, BrokerRepositoryAccess

### Community 0 - "Automation Script Installation"
Cohesion: 0.10
Nodes (25): AutomationScriptInstaller, CIProject, AutomationScriptRenderer, URL, AutomationScript, String, AutomationScriptInstallResult, AutomationScriptInstaller (+17 more)

### Community 20 - "Automation Script Models"
Cohesion: 0.17
Nodes (9): AutomationScriptVariable, Bool, AutomationScriptFile, AutomationScript, AutomationScriptInstallSnapshot, ServiceState, URL, AutomationScriptInstallResult (+1 more)

### Community 15 - "Broker Managed Repos & Registry"
Cohesion: 0.16
Nodes (21): Codable, Equatable, LocalBrokerConstants, TimeInterval, BrokerRegistry, BrokerManagedRepo, BrokerRunnerProfile, Int (+13 more)

### Community 4 - "Project CI Service & Config"
Cohesion: 0.09
Nodes (18): text, ProjectCIService, String, CIProject, RunnerConfiguration, Int, ProjectCIService, DashboardConfig (+10 more)

### Community 60 - "Automation Script Naming"
Cohesion: 0.33
Nodes (5): AutomationScriptNaming, String, UnicodeScalar, Bool, AutomationScript

### Community 30 - "Installed Scripts & Snapshots"
Cohesion: 0.21
Nodes (10): InstalledAutomationScript, AutomationScript, GitHubWorkflow, String, ServiceState, AutomationScript, Set, ProjectCISnapshot (+2 more)

### Community 41 - "Automation Script Renderer"
Cohesion: 0.29
Nodes (5): AutomationScriptRenderer, AutomationScript, CIProject, String, AutomationScriptFile

### Community 42 - "Automation Script Seed Provider"
Cohesion: 0.35
Nodes (5): AutomationScriptSeedProvider, AutomationScript, String, AutomationScriptVariable, AutomationScriptFile

### Community 33 - "Automation Script Seeds (PR templates)"
Cohesion: 0.15
Nodes (12): branchName, commitMessage, defaultSeedID, detail, files, id, pullRequestBody, pullRequestTitle (+4 more)

### Community 34 - "Automation Script Seeds (PR templates)"
Cohesion: 0.15
Nodes (12): branchName, commitMessage, defaultSeedID, detail, files, id, pullRequestBody, pullRequestTitle (+4 more)

### Community 35 - "Automation Script Seeds (PR templates)"
Cohesion: 0.15
Nodes (12): branchName, commitMessage, defaultSeedID, detail, files, id, pullRequestBody, pullRequestTitle (+4 more)

### Community 31 - "Automation Script Storage"
Cohesion: 0.25
Nodes (7): AutomationScriptStore, AutomationScript, String, AutomationScriptFile, Set, AutomationScript, String

### Community 7 - "Automation Script Store"
Cohesion: 0.18
Nodes (8): AutomationScriptStore, AutomationScript, String, URL, JSONEncoder, FileManager, Bool, Set

### Community 21 - "Automation Script Validation"
Cohesion: 0.24
Nodes (7): AutomationScriptValidator, AutomationScript, String, AutomationScriptFile, AutomationScriptVariable, Bool, String

### Community 69 - "App Entry Point"
Cohesion: 0.50
Nodes (3): CI_ScopeApp, App, Scene

### Community 61 - "Run Row UI"
Cohesion: 0.29
Nodes (5): RunRow, GitHubRun, ServiceState, Color, String

### Community 19 - "ContentView & Workspace Tabs"
Cohesion: 0.17
Nodes (7): CIProject, Bool, Date, String, ServiceState, ContentView, WorkspaceTab

### Community 43 - "Runner Work Strips UI"
Cohesion: 0.36
Nodes (11): View, RunnerWorkSection, String, RunnerWorkItem, RunnerWorkEmptyRow, RunnerWorkRow, RunnerLabelStrip, RunnerStatePill (+3 more)

### Community 53 - "Actions Runner Scope"
Cohesion: 0.31
Nodes (8): ActionsRunnerConfig, String, ActionsRunnerScope, ActionsRunnerScope, organization, personalAccount, repository, DashboardConfig

### Community 32 - "Job Notification Banner UI"
Cohesion: 0.19
Nodes (13): JobNotificationOverlay, NotificationManager, JobNotificationBanner, JobArrivalNotification, Void, Bool, JobNotificationPrimaryLine, RunnerWorkItem (+5 more)

### Community 8 - "Local Broker Service & Errors"
Cohesion: 0.11
Nodes (16): LocalBrokerService, String, ActionsRunnerConfig, URL, Bool, LocalBrokerError, missingResource, launchAgent (+8 more)

### Community 17 - "Workflow Job Codable Models"
Cohesion: 0.10
Nodes (21): CodingKeys, slug, state, queuedCount, lastCheckedAt, lastError, profileID, profileTitle (+13 more)

### Community 64 - "Runner Label Codable Model"
Cohesion: 0.33
Nodes (6): CodingKey, CodingKeys, id, name, path, state

### Community 9 - "Broker State Models"
Cohesion: 0.16
Nodes (15): LocalBrokerService, Bool, RunnerMonitorSnapshot, BrokerRunnerProfile, BrokerRegistry, BrokerState, RunnerLaunchStatus, RunnerSubRunnerSnapshot (+7 more)

### Community 22 - "GitHub Actions Runner Config"
Cohesion: 0.18
Nodes (15): GitHubAuthSnapshot, ServiceState, String, RunnerConfiguration, LocalRunnerInfo, ActionsRunnerConfig, GitHubRunnerList, GitHubActionsRunner (+7 more)

### Community 26 - "Project CI Panel UI"
Cohesion: 0.12
Nodes (13): ProjectCIPanel, CIProject, ProjectCISnapshot, Bool, AutomationScript, AutomationScriptInstallSnapshot, Void, String (+5 more)

### Community 14 - "Project CI Runner Loading"
Cohesion: 0.22
Nodes (10): ProjectCIService, CIProject, Bool, ProjectLocalRunnerStatus, LocalRunnerInfo, LoadResponse, GitHubActionsRunner, String (+2 more)

### Community 36 - "Project Dashboard UI"
Cohesion: 0.19
Nodes (11): ProjectWorkflowList, GitHubWorkflow, ProjectRunList, GitHubRun, ErrorBox, String, LimitedStatusRow, ServiceState (+3 more)

### Community 55 - "Project Context Menu UI"
Cohesion: 0.28
Nodes (8): ProjectMenuRow, CIProject, ServiceState, Bool, Void, String, Color, ProjectContextMenu

### Community 57 - "Script Removal UI"
Cohesion: 0.36
Nodes (7): ProjectScriptRemovalList, InstalledAutomationScript, AutomationScript, AutomationScriptInstallSnapshot, Void, ProjectScriptRemovalRow, ServiceState

### Community 48 - "Project Menu Panel UI"
Cohesion: 0.27
Nodes (10): ProjectMenuPanel, WorkspaceTab, CIProject, ServiceState, Int, Void, String, WorkspaceMenuRow (+2 more)

### Community 23 - "GitHub Run Codable Models"
Cohesion: 0.12
Nodes (16): String, WorkflowRunList, WorkflowRun, CodingKeys, WorkflowRun, Int64, id, name (+8 more)

### Community 44 - "Workflow Run Context"
Cohesion: 0.21
Nodes (8): RunnerFleetService, ActionsRunnerConfig, FleetLocalRunnerInfo, FleetLoadResponse, FleetGitHubActionsRunner, WorkflowRunContext, JobContext, workflowRuns

### Community 16 - "Runner Fleet Service"
Cohesion: 0.18
Nodes (9): RunnerFleetService, String, RunnerLaunchStatus, ActionsRunnerConfig, FleetLocalRunnerInfo, FleetGitHubActionsRunner, Bool, FleetRunnerConfiguration (+1 more)

### Community 1 - "Webhook & Delivery Codable Models"
Cohesion: 0.06
Nodes (48): RunnerFleetSnapshot, RunnerMonitorSnapshot, String, ServiceState, Int, JobArrivalNotification, RunnerWorkItem, Date (+40 more)

### Community 29 - "Runner Fleet Loading"
Cohesion: 0.19
Nodes (10): RunnerFleetService, DashboardConfig, Bool, RunnerFleetSnapshot, ActionsRunnerConfig, RunnerMonitorSnapshot, FleetLoadResponse, FleetGitHubActionsRunner (+2 more)

### Community 50 - "Runner Work Items"
Cohesion: 0.36
Nodes (6): FleetLocalRunnerInfo, String, Int, RunnerWorkItem, WorkflowRunContext, WorkflowJob

### Community 11 - "Broker State Monitor"
Cohesion: 0.14
Nodes (12): RunnerFleetViewModel, RunnerFleetService, LocalBrokerService, BrokerStateMonitor, String, MainActor, BrokerStateMonitor, Void (+4 more)

### Community 58 - "Runner Sub-Runner Metrics UI"
Cohesion: 0.36
Nodes (7): RunnerSubRunnerDisclosure, RunnerSubRunnerSnapshot, RunnerSubRunnerRow, String, RunnerMiniMetric, RunnerMetric, ServiceState

### Community 51 - "Runner Webhook / Status Strips"
Cohesion: 0.24
Nodes (8): RunnerWebhookStrip, BrokerWebhookStatus, Color, String, RunnerErrorStrip, RunnerEmptyState, color(), ServiceState

### Community 37 - "Runners View UI"
Cohesion: 0.19
Nodes (12): RunnersView, RunnerFleetViewModel, RunnerFleetSummary, RunnerFleetSnapshot, Bool, GridItem, String, RunnerSummaryTile (+4 more)

### Community 40 - "Script Editor Form Fields"
Cohesion: 0.24
Nodes (10): ScriptEditorPanel, AutomationScript, ScriptEditorSection, String, Void, ScriptDetailsEditor, Binding, LabeledTextField (+2 more)

### Community 62 - "Script Files Editor UI"
Cohesion: 0.33
Nodes (5): ScriptFilesEditor, AutomationScript, AutomationScriptFile, ScriptFileCard, Void

### Community 38 - "Script Install Panel UI"
Cohesion: 0.19
Nodes (12): ScriptInstallPanel, AutomationScript, CIProject, AutomationScriptInstallMode, String, AutomationScriptInstallSnapshot, Void, Binding (+4 more)

### Community 59 - "Script Install Submenu UI"
Cohesion: 0.25
Nodes (7): ScriptInstallSubmenu, AutomationScript, CIProject, AutomationScriptInstallMode, String, AutomationScriptInstallSnapshot, Void

### Community 65 - "Script Library UI"
Cohesion: 0.53
Nodes (5): ScriptLibraryList, AutomationScript, Bool, Void, ScriptLibraryRow

### Community 52 - "Script List Row UI"
Cohesion: 0.20
Nodes (9): ScriptListRow, AutomationScript, Bool, CIProject, AutomationScriptInstallMode, String, AutomationScriptInstallSnapshot, Void (+1 more)

### Community 56 - "Script Variables Editor UI"
Cohesion: 0.25
Nodes (7): ScriptVariablesEditor, AutomationScript, AutomationScriptVariable, ScriptVariableCard, Void, Binding, String

### Community 13 - "Scripts View & Editor"
Cohesion: 0.14
Nodes (14): ScriptsView, AutomationScriptStore, AutomationScriptInstallViewModel, CIProject, Void, AutomationScript, String, AutomationScriptInstallMode (+6 more)

### Community 45 - "Shared UI Components"
Cohesion: 0.21
Nodes (10): FileOpenButton, String, Bool, PanelShell, Content, LogScroll, EmptyState, StatusDot (+2 more)

### Community 46 - "Shell Client"
Cohesion: 0.32
Nodes (7): ShellResult, Int32, String, ShellClient, TimeInterval, DashboardConfig, Process

### Community 12 - "Function-Length Linter (Python)"
Cohesion: 0.20
Nodes (28): Issue, FunctionBlock, main(), str, int, parse_args(), Namespace, load_config() (+20 more)

### Community 27 - "Runner Setup Script (Python)"
Cohesion: 0.27
Nodes (13): setup-ci-scope-runners.sh script, usage(), fail(), require_command(), ensure_runner_package(), service_status(), stop_existing_service(), remove_existing_config() (+5 more)

### Community 5 - "Build & Warning Annotation (Python)"
Cohesion: 0.16
Nodes (37): SwiftProject, WarningRecord, str, WarningPolicy, BuildResult, main(), int, parse_args() (+29 more)

### Community 6 - "Swift Path Discovery & Linting (Python)"
Cohesion: 0.20
Nodes (33): SwiftProject, main(), str, int, parse_args(), Namespace, run_stage(), Path (+25 more)

### Community 63 - "Security Hardening Log"
Cohesion: 0.29
Nodes (6): 2025-02-12 - Prevent Command Injection via String Interpolation, 2024-06-04 - Safely Append URL Path Components, 2024-05-18 - [Add strict validation to repository URL inputs], 2024-05-24 - Validate System Command Input, 2025-02-12 - Secure Info.plist by Enforcing ATS, 2025-02-14 - Prevent Terminal Injection

### Community 24 - "README / Documentation"
Cohesion: 0.12
Nodes (16): CI Scope, Status, What It Does, Project Model, Automation Scripts, Local Configuration, Requirements, Runner Model (+8 more)

## Knowledge Gaps
- **409 isolated node(s):** `accessLevel`, `indentBlankLines`, `indentConditionalCompilationBlocks`, `indentSwitchCaseLabels`, `spaces` (+404 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **3 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `View` connect `Runner Work Strips UI` to `Scripts View & Editor`, `ContentView & Workspace Tabs`, `Project CI Panel UI`, `Job Notification Banner UI`, `Project Dashboard UI`, `Runners View UI`, `Script Install Panel UI`, `Script Editor Form Fields`, `Shared UI Components`, `Project Menu Panel UI`, `Runner Webhook / Status Strips`, `Script List Row UI`, `Project Context Menu UI`, `Script Variables Editor UI`, `Script Removal UI`, `Runner Sub-Runner Metrics UI`, `Script Install Submenu UI`, `Run Row UI`, `Script Files Editor UI`, `Script Library UI`?**
  _High betweenness centrality (0.213) - this node is a cross-community bridge._
- **Why does `ScriptsView` connect `Scripts View & Editor` to `Runner Work Strips UI`?**
  _High betweenness centrality (0.212) - this node is a cross-community bridge._
- **Why does `ScriptEditorSection` connect `Scripts View & Editor` to `Install Mode & Workspace Enums`, `Script Variable Kinds`?**
  _High betweenness centrality (0.209) - this node is a cross-community bridge._
- **What connects `accessLevel`, `indentBlankLines`, `indentConditionalCompilationBlocks` to the rest of the system?**
  _409 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Swift-Format Configuration` be split into smaller, more focused modules?**
  _Cohesion score 0.046511627906976744 - nodes in this community are weakly interconnected._
- **Should `Automation Script Errors` be split into smaller, more focused modules?**
  _Cohesion score 0.08292682926829269 - nodes in this community are weakly interconnected._
- **Should `Install Mode & Workspace Enums` be split into smaller, more focused modules?**
  _Cohesion score 0.14285714285714285 - nodes in this community are weakly interconnected._