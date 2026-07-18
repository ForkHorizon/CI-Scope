import SwiftUI

/// Repo-centric overview: a row per project, a column per managed gate, a cell
/// showing installed (check) or missing (one click to install that gate).
struct GateMatrixView: View {
    let projects: [CIProject]
    let gateScripts: [AutomationScript]
    @ObservedObject var installViewModel: AutomationScriptInstallViewModel
    let onInstalled: (CIProject) -> Void

    @StateObject private var model = GateMatrixViewModel()
    @State private var lastActionScriptID: String?

    var body: some View {
        PanelShell(title: "Gate Coverage", icon: "tablecells") {
            VStack(spacing: 0) {
                toolbar
                if projects.isEmpty {
                    EmptyState(icon: "tablecells", text: "No projects")
                        .frame(maxHeight: .infinity)
                } else {
                    ScrollView([.horizontal, .vertical]) {
                        grid.padding(12)
                    }
                    statusBar
                }
            }
        }
        .padding(14)
        .task { await model.load(projects) }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Text("Which gates are installed on each repository")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if model.isLoading {
                ProgressView().controlSize(.small)
            }
            Button {
                Task { await model.load(projects) }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .disabled(model.isLoading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var grid: some View {
        Grid(alignment: .center, horizontalSpacing: 10, verticalSpacing: 8) {
            GridRow {
                Text("Repository")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 210, alignment: .leading)
                ForEach(gateScripts) { script in
                    Text(shortName(script))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 74)
                }
            }
            Divider()
            ForEach(projects) { project in
                GridRow {
                    Text(project.repositorySlug)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(width: 210, alignment: .leading)
                    ForEach(gateScripts) { script in
                        cell(project: project, script: script)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cell(project: CIProject, script: AutomationScript) -> some View {
        if model.isInstalled(script, projectID: project.id) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .frame(width: 74)
                .help("\(script.title) installed")
        } else {
            Button {
                install(script, into: project)
            } label: {
                Image(systemName: "plus.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 74)
            .disabled(installViewModel.snapshot(for: script).isInstalling)
            .help("Install \(script.title) on \(project.repositorySlug)")
        }
    }

    @ViewBuilder
    private var statusBar: some View {
        if let id = lastActionScriptID, let script = gateScripts.first(where: { $0.id == id }) {
            AutomationScriptInstallStatusBox(status: installViewModel.snapshot(for: script))
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
        }
    }

    private func install(_ script: AutomationScript, into project: CIProject) {
        lastActionScriptID = script.id
        installViewModel.install(
            script: script,
            project: project,
            variableValues: defaultValues(for: script),
            mode: .localBroker
        ) {
            onInstalled(project)
            Task { await model.load(projects) }
        }
    }

    private func defaultValues(for script: AutomationScript) -> [String: String] {
        Dictionary(uniqueKeysWithValues: script.variables.map { ($0.id, $0.defaultValue) })
    }

    private func shortName(_ script: AutomationScript) -> String {
        switch script.defaultSeedID ?? script.id {
        case "ai-readability": "300 L"
        case "swift-compile-gate": "Compile"
        case "swift-quality-gate": "Quality"
        case "web-quality-gate": "Web"
        case "python-quality-gate": "Python"
        case "unity-quality-gate": "Unity"
        case "slop-review": "Slop"
        default: String(script.title.prefix(7))
        }
    }
}
