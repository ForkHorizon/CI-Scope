import SwiftUI

/// Repo-centric coverage: one row per project with a dot per managed gate and an installed count.
/// Expanding a row lists the gates with a one-click install for the missing ones.
struct GateMatrixView: View {
    let projects: [CIProject]
    let gateScripts: [AutomationScript]
    @ObservedObject var installViewModel: AutomationScriptInstallViewModel
    let onInstalled: (CIProject) -> Void

    @StateObject private var model = GateMatrixViewModel()
    @State private var lastActionScriptID: String?
    @State private var expandedProjectID: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero
                if projects.isEmpty {
                    EmptyState(icon: "tablecells", text: "No projects")
                } else {
                    VStack(spacing: 0) {
                        ForEach(projects) { project in
                            projectRow(project)
                        }
                    }
                }
                statusBar
            }
            .padding(22)
        }
        .task { await model.load(projects) }
    }

    private var installedTotal: Int {
        projects.reduce(0) { total, project in
            total + gateScripts.filter { model.isInstalled($0, projectID: project.id) }.count
        }
    }

    private var hero: some View {
        HStack(alignment: .bottom, spacing: 28) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Gates installed").nothingCaption()
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(installedTotal)").nothingDisplay(56).foregroundStyle(NothingTheme.green)
                    Text("/ \(projects.count * gateScripts.count)").nothingDisplay(24).foregroundStyle(NothingTheme.inkDim)
                }
            }
            Spacer()
            if model.isLoading { ProgressView().controlSize(.small) }
            Button("Refresh", systemImage: "arrow.clockwise") { Task { await model.load(projects) } }
                .buttonStyle(.pill)
                .disabled(model.isLoading)
        }
    }

    private func projectRow(_ project: CIProject) -> some View {
        let installed = gateScripts.filter { model.isInstalled($0, projectID: project.id) }
        let isOpen = expandedProjectID == project.id
        return VStack(spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { expandedProjectID = isOpen ? nil : project.id }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10))
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                        .foregroundStyle(NothingTheme.inkDim)
                    repoName(project)
                    Spacer(minLength: 8)
                    HStack(spacing: 5) {
                        ForEach(gateScripts) { script in
                            Circle()
                                .fill(installed.contains { $0.id == script.id } ? NothingTheme.green : Color.clear)
                                .overlay(
                                    Circle().stroke(
                                        installed.contains { $0.id == script.id } ? NothingTheme.green : NothingTheme.lineStrong,
                                        lineWidth: 1)
                                )
                                .frame(width: 8, height: 8)
                        }
                    }
                    Text("\(installed.count)/\(gateScripts.count)")
                        .font(NothingTheme.small.monospacedDigit())
                        .foregroundStyle(installed.isEmpty ? NothingTheme.inkDim : NothingTheme.ink)
                        .frame(width: 34, alignment: .trailing)
                }
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isOpen { gateList(project, installed: installed) }
            Rectangle().fill(NothingTheme.line).frame(height: 1)
        }
    }

    private func repoName(_ project: CIProject) -> some View {
        let parts = project.repositorySlug.split(separator: "/")
        return HStack(spacing: 0) {
            if parts.count == 2 {
                Text("\(parts[0])/").foregroundStyle(NothingTheme.inkDim)
                Text(String(parts[1])).foregroundStyle(NothingTheme.ink).fontWeight(.medium)
            } else {
                Text(project.repositorySlug).foregroundStyle(NothingTheme.ink)
            }
        }
        .font(NothingTheme.body)
        .lineLimit(1)
        .truncationMode(.middle)
    }

    private func gateList(_ project: CIProject, installed: [AutomationScript]) -> some View {
        VStack(spacing: 0) {
            ForEach(gateScripts) { script in
                let isInstalled = installed.contains { $0.id == script.id }
                HStack(spacing: 12) {
                    StatusDot(state: isInstalled ? .online : .unknown)
                    Text(script.title).font(NothingTheme.small)
                        .foregroundStyle(isInstalled ? NothingTheme.ink : NothingTheme.inkDim)
                    Spacer()
                    if isInstalled {
                        Text("installed").nothingCaption()
                    } else {
                        Button("Install") { install(script, into: project) }
                            .buttonStyle(.pill)
                            .disabled(installViewModel.snapshot(for: script).isInstalling)
                    }
                }
                .padding(.vertical, 6)
                .padding(.leading, 22)
            }
        }
        .padding(.bottom, 10)
    }

    @ViewBuilder private var statusBar: some View {
        if let id = lastActionScriptID, let script = gateScripts.first(where: { $0.id == id }) {
            AutomationScriptInstallStatusBox(status: installViewModel.snapshot(for: script))
        }
    }

    private func install(_ script: AutomationScript, into project: CIProject) {
        lastActionScriptID = script.id
        installViewModel.install(
            script: script,
            project: project,
            variableValues: Dictionary(uniqueKeysWithValues: script.variables.map { ($0.id, $0.defaultValue) }),
            mode: .localRunner
        ) {
            onInstalled(project)
            Task { await model.load(projects) }
        }
    }
}
