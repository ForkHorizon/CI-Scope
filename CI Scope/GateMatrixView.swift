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
    @State private var hoveredProjectID: String?

    private let repoColumnWidth: CGFloat = 190
    private let gateColumnWidth: CGFloat = 52

    var body: some View {
        PanelShell(title: "Gate Coverage", icon: "tablecells") {
            VStack(spacing: 0) {
                toolbar
                if projects.isEmpty {
                    EmptyState(icon: "tablecells", text: "No projects")
                        .frame(maxHeight: .infinity)
                } else {
                    ScrollView([.horizontal, .vertical]) {
                        VStack(spacing: 0) {
                            headerRow
                            Divider()
                                .padding(.vertical, 4)
                            ForEach(Array(projects.enumerated()), id: \.element.id) { index, project in
                                projectRow(index: index, project: project)
                                if index < projects.count - 1 {
                                    Divider()
                                        .opacity(0.35)
                                }
                            }
                        }
                        .padding(12)
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
            Text("Overview of installed quality gates per repository")
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

    private var headerRow: some View {
        HStack(spacing: 4) {
            Text("Repository")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: repoColumnWidth, alignment: .leading)
                .padding(.leading, 8)
            ForEach(gateScripts) { script in
                VStack(spacing: 1) {
                    let parts = headerTitle(script)
                    Text(parts.top)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.primary)
                    if !parts.bottom.isEmpty {
                        Text(parts.bottom)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .multilineTextAlignment(.center)
                .frame(width: gateColumnWidth)
                .help(script.title)
            }
        }
        .padding(.vertical, 4)
    }

    private func projectRow(index: Int, project: CIProject) -> some View {
        let isHovered = hoveredProjectID == project.id
        return HStack(spacing: 4) {
            repoCell(project: project)
                .frame(width: repoColumnWidth, alignment: .leading)
                .padding(.leading, 8)
            ForEach(gateScripts) { script in
                cell(project: project, script: script)
                    .frame(width: gateColumnWidth)
            }
        }
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.accentColor.opacity(0.12) : (index % 2 == 0 ? Color.primary.opacity(0.025) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isHovered ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                hoveredProjectID = hovering ? project.id : nil
            }
        }
    }

    @ViewBuilder
    private func repoCell(project: CIProject) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.fill")
                .font(.caption)
                .foregroundStyle(Color.accentColor)
            let parts = project.repositorySlug.split(separator: "/")
            if parts.count == 2 {
                Text(styledSlug(owner: parts[0], name: parts[1]))
            } else {
                Text(project.repositorySlug)
                    .font(.caption.weight(.semibold))
            }
        }
        .lineLimit(1)
        .truncationMode(.middle)
    }

    /// `Text` concatenation via `+` is deprecated (macOS 26); build one
    /// AttributedString with per-run styling instead so "owner/" stays
    /// secondary and dimmer while the repo name stays bold and primary.
    private func styledSlug(owner: Substring, name: Substring) -> AttributedString {
        var result = AttributedString("\(owner)/")
        result.font = .caption2
        result.foregroundColor = .secondary
        var nameRun = AttributedString(String(name))
        nameRun.font = .caption.weight(.semibold)
        nameRun.foregroundColor = .primary
        result.append(nameRun)
        return result
    }

    @ViewBuilder
    private func cell(project: CIProject, script: AutomationScript) -> some View {
        if model.isInstalled(script, projectID: project.id) {
            Image(systemName: "checkmark.circle.fill")
                .font(.body)
                .foregroundStyle(.green)
                .help("\(script.title) is installed on \(project.repositorySlug)")
        } else {
            Button {
                install(script, into: project)
            } label: {
                Image(systemName: "plus.circle")
                    .font(.body)
                    .foregroundStyle(.secondary.opacity(0.7))
            }
            .buttonStyle(.plain)
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
            mode: .localRunner
        ) {
            onInstalled(project)
            Task { await model.load(projects) }
        }
    }

    private func defaultValues(for script: AutomationScript) -> [String: String] {
        Dictionary(uniqueKeysWithValues: script.variables.map { ($0.id, $0.defaultValue) })
    }

    private func headerTitle(_ script: AutomationScript) -> (top: String, bottom: String) {
        switch script.defaultSeedID ?? script.id {
        case "code-linter": return ("Code", "Linter")
        case "swift-compile-gate": return ("Swift", "Compile")
        case "swift-quality-gate": return ("Swift", "Quality")
        case "web-quality-gate": return ("Web", "Quality")
        case "python-quality-gate": return ("Python", "Quality")
        case "go-quality-gate": return ("Go", "Quality")
        case "unity-quality-gate": return ("Unity", "Quality")
        case "slop-review": return ("Slop", "Review")
        default:
            let words = script.title.split(separator: " ").map(String.init)
            if words.count >= 2 {
                return (words[0], words.dropFirst().joined(separator: " "))
            }
            return (script.title, "")
        }
    }
}
