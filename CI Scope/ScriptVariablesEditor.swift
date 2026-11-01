import SwiftUI

struct ScriptVariablesEditor: View {
    @Binding var script: AutomationScript

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach($script.variables) { $variable in
                ScriptVariableCard(variable: $variable) {
                    remove(variable)
                }
            }
            Button("Add variable") { script.variables.append(.empty()) }
                .buttonStyle(.pill)
        }
    }

    private func remove(_ variable: AutomationScriptVariable) {
        script.variables.removeAll { $0.id == variable.id }
    }
}

struct ScriptVariableCard: View {
    @Binding var variable: AutomationScriptVariable
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("variable_id", text: $variable.id)
                    .textFieldStyle(.roundedBorder)
                Picker("Kind", selection: $variable.kind) {
                    ForEach(AutomationScriptVariableKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .frame(width: 128)
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "trash")
                }
            }

            LabeledTextField(title: "Title", text: $variable.title)
            LabeledTextEditor(title: "Help", text: $variable.help, minHeight: 52)
            LabeledTextField(title: "Default value", text: $variable.defaultValue)
            if variable.kind == .option {
                LabeledTextField(title: "Options, comma separated", text: optionsBinding)
            }
            Toggle("Required", isOn: $variable.isRequired)
        }
        .padding(12)
        .nothingCard(radius: 12)
    }

    private var optionsBinding: Binding<String> {
        Binding(
            get: { variable.options.joined(separator: ", ") },
            set: { value in
                variable.options = value.split(separator: ",").map { String($0).trimmed }
            }
        )
    }
}
