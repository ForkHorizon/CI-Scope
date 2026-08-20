import AppKit
import SwiftUI

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
