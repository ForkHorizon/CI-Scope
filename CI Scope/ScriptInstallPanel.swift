import AppKit
import SwiftUI

struct ScriptInstallVariableInput: View {
    let variable: AutomationScriptVariable
    @Binding var values: [String: String]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(variable.title)
                .font(NothingTheme.small.weight(.semibold))
                .foregroundStyle(NothingTheme.inkDim)
            input
            if !variable.help.isEmpty {
                Text(variable.help)
                    .font(NothingTheme.tiny)
                    .foregroundStyle(NothingTheme.inkDim)
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
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 66)
                .background(NothingTheme.panel, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(NothingTheme.line, lineWidth: 1))
        case .option:
            Picker(variable.title, selection: valueBinding) {
                ForEach(variable.options, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .labelsHidden()
        case .number, .text:
            TextField(variable.title, text: valueBinding)
                .nothingField()
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
                    .font(NothingTheme.small.weight(.semibold))
                    .lineLimit(1)
                Text(status.detail)
                    .font(NothingTheme.tiny)
                    .foregroundStyle(NothingTheme.inkDim)
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
        .padding(12)
        .nothingCard(radius: 12)
    }
}
