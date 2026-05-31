import AppKit
import SwiftUI

struct ScriptInstallPanel: View {
    let script: AutomationScript?
    let projects: [CIProject]
    @Binding var selectedProjectID: CIProject.ID?
    @Binding var variableValues: [String: String]
    let snapshot: AutomationScriptInstallSnapshot
    let onInstall: () -> Void

    var body: some View {
        PanelShell(title: "Install", icon: "arrow.triangle.branch") {
            VStack(alignment: .leading, spacing: 10) {
                projectPicker
                Divider()
                variableInputs
                Spacer(minLength: 0)
                AutomationScriptInstallStatusBox(status: snapshot)
                Button(action: onInstall) {
                    Label(snapshot.isInstalling ? "Installing" : "Create Pull Request", systemImage: "arrow.up.right.square")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(script == nil || selectedProjectID == nil || snapshot.isInstalling)
            }
            .padding(10)
        }
    }

    private var projectPicker: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Target project")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Picker("Project", selection: projectSelection) {
                ForEach(projects) { project in
                    Text(project.repositorySlug).tag(Optional(project.id))
                }
            }
            .labelsHidden()
            .disabled(projects.isEmpty)
        }
    }

    @ViewBuilder
    private var variableInputs: some View {
        if let script, !script.variables.isEmpty {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(script.variables) { variable in
                        ScriptInstallVariableInput(variable: variable, values: $variableValues)
                    }
                }
            }
        } else {
            EmptyState(icon: "slider.horizontal.3", text: "No install variables")
        }
    }

    private var projectSelection: Binding<CIProject.ID?> {
        Binding(
            get: { selectedProjectID },
            set: { selectedProjectID = $0 }
        )
    }
}

struct ScriptInstallVariableInput: View {
    let variable: AutomationScriptVariable
    @Binding var values: [String: String]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(variable.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            input
            if !variable.help.isEmpty {
                Text(variable.help)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var input: some View {
        switch variable.kind {
        case .boolean:
            Toggle("Enabled", isOn: booleanBinding)
        case .multiline:
            TextEditor(text: valueBinding)
                .font(.system(size: 11, design: .monospaced))
                .frame(minHeight: 66)
        case .option:
            Picker(variable.title, selection: valueBinding) {
                ForEach(variable.options, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .labelsHidden()
        case .number, .text:
            TextField(variable.title, text: valueBinding)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var valueBinding: Binding<String> {
        Binding(
            get: { values[variable.id] ?? variable.defaultValue },
            set: { values[variable.id] = $0 }
        )
    }

    private var booleanBinding: Binding<Bool> {
        Binding(
            get: { (values[variable.id] ?? variable.defaultValue).lowercased() == "true" },
            set: { values[variable.id] = $0 ? "true" : "false" }
        )
    }
}

struct AutomationScriptInstallStatusBox: View {
    let status: AutomationScriptInstallSnapshot

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
                    .lineLimit(3)
                    .textSelection(.enabled)
            }
            Spacer()
            if let url = status.pullRequestURL {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(9)
        .background(Color.secondary.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}
