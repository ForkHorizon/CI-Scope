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
        PanelShell(title: "GitHub CI", icon: "point.3.connected.trianglepath.dotted") {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 7)
                                .fill(Color.accentColor.opacity(0.14))
                            Image(systemName: "folder.badge.gearshape")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                        .frame(width: 36, height: 36)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(project.title)
                                .font(.system(size: 17, weight: .semibold))
                                .lineLimit(1)
                            Text(project.repositorySlug)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        Spacer()

                        HStack(spacing: 6) {
                            Button {
                                copySSHURL()
                            } label: {
                                Label("Copy SSH", systemImage: "doc.on.doc")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 8)
                                    .frame(height: 28)
                                    .background(Color.secondary.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                            .help("Copy SSH URL")

                            Button {
                                openGitHubRepository()
                            } label: {
                                Label("GitHub", systemImage: "arrow.up.right.square")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 8)
                                    .frame(height: 28)
                                    .background(Color.secondary.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                            .help("Open GitHub repository")
                        }

                        if isLoading {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            StatusDot(state: snapshot?.state ?? .unknown)
                        }
                    }

                    LazyVGrid(columns: projectInfoColumns, spacing: 8) {
                        LimitedStatusRow(
                            title: "Repository", value: project.remoteURL, icon: "link", state: .online)
                        LimitedStatusRow(
                            title: "GitHub Actions", value: ciSummary, icon: "checkmark.seal",
                            state: snapshot?.state ?? .unknown)
                        LimitedStatusRow(
                            title: "MacBook runner", value: localRunnerSummary, icon: "desktopcomputer",
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
                            installViewModel: installViewModel
                        )
                        Spacer()
                    }

                    if let script = codeLinterScript, let workflow = script.matchingWorkflow(in: snapshot) {
                        codeLinterStatusRow(script: script, workflow: workflow)
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
                .padding(12)
            }
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
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8),
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
