import SwiftUI

struct ScriptInstallSubmenu: View {
    let script: AutomationScript
    let projects: [CIProject]
    @Binding var selectedProjectID: CIProject.ID?
    @Binding var runnerMode: AutomationScriptInstallMode
    @Binding var variableValues: [String: String]
    let snapshot: AutomationScriptInstallSnapshot
    let onOpenEditor: () -> Void
    let onInstall: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    projectPicker
                    runnerModePicker
                }
                .frame(width: 220, alignment: .leading)

                variableInputs
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 8) {
                AutomationScriptInstallStatusBox(status: snapshot)
                    .frame(maxWidth: .infinity)

                Button("Open editor", action: onOpenEditor).buttonStyle(.pill)

                Button(snapshot.isInstalling ? "Installing" : "Create PR", action: onInstall)
                    .buttonStyle(.pillPrimary)
                    .disabled(selectedProjectID == nil || snapshot.isInstalling)
            }
        }
        .padding(14)
    }

    private var projectPicker: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Target project")
                .font(NothingTheme.small.weight(.semibold))
                .foregroundStyle(NothingTheme.inkDim)

            Picker("Project", selection: $selectedProjectID) {
                if projects.isEmpty {
                    Text("No projects").tag(Optional<CIProject.ID>.none)
                } else {
                    ForEach(projects) { project in
                        Text(project.repositorySlug).tag(Optional(project.id))
                    }
                }
            }
            .labelsHidden()
            .disabled(projects.isEmpty)
        }
    }

    private var runnerModePicker: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Runner")
                .font(NothingTheme.small.weight(.semibold))
                .foregroundStyle(NothingTheme.inkDim)
            Picker("Runner", selection: $runnerMode) {
                ForEach(AutomationScriptInstallMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text(runnerMode.detail(for: script))
                .font(NothingTheme.tiny)
                .foregroundStyle(NothingTheme.inkDim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var variableInputs: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Variables")
                .font(NothingTheme.small.weight(.semibold))
                .foregroundStyle(NothingTheme.inkDim)

            if script.variables.isEmpty {
                Text("No install variables")
                    .font(NothingTheme.small)
                    .foregroundStyle(NothingTheme.inkDim)
                    .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 180), spacing: 10)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(script.variables) { variable in
                        ScriptInstallVariableInput(variable: variable, values: $variableValues)
                    }
                }
            }
        }
    }
}
