import AppKit
import SwiftUI

struct ProjectCIPanel: View {
    let project: CIProject
    let snapshot: ProjectCISnapshot?
    let isLoading: Bool
    let readabilityGateStatus: ReadabilityGateInstallSnapshot
    let onInstallReadabilityGate: () -> Void

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
                                onInstallReadabilityGate()
                            } label: {
                                Label(readabilityGateStatus.isInstalling ? "Installing" : "AI Gate", systemImage: "checklist.checked")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 8)
                                    .frame(height: 28)
                                    .background(Color.secondary.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                            .disabled(readabilityGateStatus.isInstalling)
                            .overlay {
                                if readabilityGateStatus.isInstalling {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                            }
                            .help("Create a PR that installs the AI Readability GitHub Action")

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
                        LimitedStatusRow(title: "Repository", value: project.remoteURL, icon: "link", state: .online)
                        LimitedStatusRow(title: "GitHub Actions", value: ciSummary, icon: "checkmark.seal", state: snapshot?.state ?? .unknown)
                        LimitedStatusRow(title: "Local runner", value: localRunnerSummary, icon: "server.rack", state: snapshot?.localRunner.state ?? .unknown)
                    }

                    if readabilityGateStatus != .idle {
                        ReadabilityGateInstallBox(status: readabilityGateStatus)
                    }

                    if let error = snapshot?.error {
                        ErrorBox(text: error)
                    }

                    if let snapshot, !snapshot.workflows.isEmpty {
                        ProjectWorkflowList(workflows: snapshot.workflows)
                    }

                    if let snapshot, !snapshot.runs.isEmpty {
                        ProjectRunList(runs: snapshot.runs)
                    }

                    if snapshot?.error == nil, snapshot?.workflows.isEmpty != false, snapshot?.runs.isEmpty != false, !isLoading {
                        EmptyState(icon: "icloud.slash", text: "No actions available")
                    }
                }
                .padding(12)
            }
        }
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

    var projectInfoColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8)
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

struct ReadabilityGateInstallBox: View {
    let status: ReadabilityGateInstallSnapshot

    var body: some View {
        HStack(spacing: 8) {
            StatusDot(state: status.state)

            VStack(alignment: .leading, spacing: 2) {
                Text(status.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(status.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 8)

            if let pullRequestURL = status.pullRequestURL {
                Button {
                    NSWorkspace.shared.open(pullRequestURL)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .help("Open pull request")
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(statusColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(statusColor.opacity(0.18))
        )
    }

    var statusColor: Color {
        switch status.state {
        case .online: .green
        case .warning: .orange
        case .offline: .red
        case .unknown: .secondary
        }
    }
}
