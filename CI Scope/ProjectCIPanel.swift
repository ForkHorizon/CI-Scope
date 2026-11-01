import AppKit
import SwiftUI

struct ProjectCIPanel: View {
    let project: CIProject
    let snapshot: ProjectCISnapshot?
    let isLoading: Bool
    let liveJobs: [RunnerWorkItem]
    let scripts: [AutomationScript]
    let isV2Managed: Bool
    @ObservedObject var v2Control: V2ClientControlSession
    let removalSnapshot: (AutomationScript) -> AutomationScriptInstallSnapshot
    let onAttachToRunner: () -> Void
    let onRemoveScript: (AutomationScript) -> Void
    @ObservedObject var installViewModel: AutomationScriptInstallViewModel
    @State var codeLinterStatus: CodeLinterWorkflowStatus = .unavailable

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 8) {
                    Button("Copy SSH", action: copySSHURL).buttonStyle(.pill).help("Copy SSH URL")
                    Button("GitHub", action: openGitHubRepository).buttonStyle(.pill)
                        .help("Open GitHub repository")
                    Spacer()
                    if isLoading { ProgressView().controlSize(.small) }
                }

                LazyVGrid(columns: projectInfoColumns, spacing: 0) {
                    LimitedStatusRow(
                        title: "Repository", value: project.remoteURL, state: .online)
                    LimitedStatusRow(
                        title: "GitHub Actions", value: ciSummary,
                        state: snapshot?.state ?? .unknown)
                    LimitedStatusRow(
                        title: "CI mode", value: ciModeSummary,
                        state: ciModeState)
                    LimitedStatusRow(
                        title: "MacBook runner", value: localRunnerSummary,
                        state: snapshot?.localRunner.state ?? .unknown)
                    runnerAccessRow
                    if V2ClientFeature.statusAdapterEnabled() {
                        v2StatusRow
                    }
                    if v2Control.isV2ControlVisible {
                        v2ControlRow
                    }
                }

                HStack {
                    RecommendedGatesButton(
                        project: project,
                        scripts: scripts,
                        isInstalled: { $0.matchingWorkflow(in: snapshot) != nil },
                        manifestCheckTypes: snapshot?.unifiedChecks.map { Set($0.manifest.checks.map(\.type)) },
                        installViewModel: installViewModel
                    )
                    Spacer()
                }

                if let script = codeLinterScript, let workflow = script.matchingWorkflow(in: snapshot) {
                    codeLinterStatusRow(script: script, workflow: workflow)
                }

                if let unifiedChecks = snapshot?.unifiedChecks {
                    UnifiedChecksSection(snapshot: unifiedChecks)
                }

                if let localCheck = snapshot?.localCheck {
                    LocalCheckSection(result: localCheck, runs: snapshot?.runs ?? [])
                }

                if let error = snapshot?.unifiedChecksError {
                    ErrorBox(text: "Unified checks: \(error)")
                }

                if let error = snapshot?.error {
                    ErrorBox(text: error)
                }

                if !liveJobs.isEmpty {
                    ProjectLiveWorkSection(items: liveJobs)
                }

                if !installedScripts.isEmpty {
                    ProjectScriptRemovalList(
                        installedScripts: installedScripts,
                        snapshot: removalSnapshot,
                        onRemove: onRemoveScript
                    )
                }

                if !unmanagedWorkflows.isEmpty {
                    ProjectWorkflowList(workflows: unmanagedWorkflows)
                }

                if let snapshot, !snapshot.runs.isEmpty {
                    ProjectRunList(runs: snapshot.runs)
                }

                if snapshot?.error == nil, snapshot?.workflows.isEmpty != false,
                    snapshot?.runs.isEmpty != false, !isLoading
                {
                    EmptyState(icon: "icloud.slash", text: "No actions available")
                }
            }
            .padding(22)
        }
        .task(id: codeLinterWorkflowPath) { await refreshCodeLinterStatus() }
    }

    var ciSummary: String {
        guard let snapshot else {
            return isLoading ? "Loading" : "Not loaded"
        }
        if let error = snapshot.error, !error.isEmpty {
            if snapshot.workflows.isEmpty && snapshot.runs.isEmpty {
                return "Error"
            }
            let runs = snapshot.runs.isEmpty ? "runs unavailable" : "\(snapshot.runs.count) runs"
            return "\(snapshot.workflows.count) workflows · \(runs)"
        }
        if snapshot.workflows.isEmpty && snapshot.runs.isEmpty {
            return "No actions available"
        }
        return "\(snapshot.workflows.count) workflows · \(snapshot.runs.count) runs"
    }

    var ciModeSummary: String {
        if let count = snapshot?.unifiedChecks?.manifest.checks.count {
            return "Unified · \(count) checks"
        }
        if snapshot?.unifiedChecksError != nil { return "Manifest unavailable" }
        return "Legacy workflows"
    }

    var ciModeState: ServiceState {
        if snapshot?.unifiedChecks != nil { return .online }
        if snapshot?.unifiedChecksError != nil { return .warning }
        return .unknown
    }

    var installedScripts: [InstalledAutomationScript] {
        guard snapshot != nil else { return [] }

        let matches = scripts.compactMap { script -> InstalledAutomationScript? in
            guard let workflow = script.matchingWorkflow(in: snapshot) else { return nil }
            return InstalledAutomationScript(script: script, workflow: workflow)
        }

        return matches.reduce(into: []) { result, match in
            guard let workflowPath = match.workflow.path?.normalizedWorkflowPath else {
                result.append(match)
                return
            }
            if let existingIndex = result.firstIndex(where: {
                $0.workflow.path?.normalizedWorkflowPath == workflowPath
            }) {
                if match.workflow.name == match.script.title {
                    result[existingIndex] = match
                }
            } else {
                result.append(match)
            }
        }
    }

    var unmanagedWorkflows: [GitHubWorkflow] {
        let managedPaths = Set(installedScripts.compactMap { $0.workflow.path?.normalizedWorkflowPath })
        return snapshot?.workflows.filter { workflow in
            guard let path = workflow.path?.normalizedWorkflowPath else { return true }
            return !managedPaths.contains(path)
        } ?? []
    }

    var projectInfoColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 24),
            GridItem(.flexible(), spacing: 24),
        ]
    }

    var localRunnerSummary: String {
        guard let runner = snapshot?.localRunner else {
            return isLoading ? "Checking" : "Not loaded"
        }
        if runner.detail == "-" || runner.detail.isEmpty {
            return runner.summary
        }
        if runner.summary.hasPrefix("Registered to") {
            return runner.summary
        }
        return "\(runner.summary) · \(runner.detail)"
    }

    var sshURL: String {
        "git@github.com:\(project.repositorySlug).git"
    }

    var githubURL: URL {
        URL(string: "https://github.com/\(project.repositorySlug)")!
    }

    func copySSHURL() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(sshURL, forType: .string)
    }

    func openGitHubRepository() {
        NSWorkspace.shared.open(githubURL)
    }
}

extension String {
    fileprivate var normalizedWorkflowPath: String {
        trimmed
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
    }
}
