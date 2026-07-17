import SwiftUI

struct ScriptEditorPanel: View {
    @Binding var script: AutomationScript
    @Binding var section: ScriptEditorSection

    let errorMessage: String?
    let onSave: () -> Void
    let onReset: () -> Void

    var body: some View {
        PanelShell(title: "Script Editor", icon: "slider.horizontal.3") {
            VStack(spacing: 8) {
                editorToolbar
                if let errorMessage {
                    ErrorBox(text: errorMessage)
                        .padding(.horizontal, 10)
                }
                ScrollView {
                    currentSection
                        .padding(10)
                }
            }
        }
    }

    private var editorToolbar: some View {
        HStack(spacing: 8) {
            Picker("Section", selection: $section) {
                ForEach(ScriptEditorSection.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Button("Save", action: onSave)
                .keyboardShortcut("s", modifiers: [.command])
            Button("Reset", action: onReset)
                .disabled(script.defaultSeedID == nil)
        }
        .padding(10)
    }

    @ViewBuilder
    private var currentSection: some View {
        switch section {
        case .details:
            ScriptDetailsEditor(script: $script)
        case .variables:
            ScriptVariablesEditor(script: $script)
        case .files:
            ScriptFilesEditor(script: $script)
        }
    }
}

struct ScriptDetailsEditor: View {
    @Binding var script: AutomationScript

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledTextField(title: "ID", text: $script.id)
            LabeledTextField(title: "Title", text: $script.title)
            LabeledTextField(title: "Summary", text: $script.summary)
            LabeledTextEditor(title: "Detail", text: $script.detail, minHeight: 70)
            LabeledTextField(title: "Runner labels / runs-on", text: runnerLabelsBinding)
            LabeledTextField(title: "Branch name", text: $script.branchName)
            LabeledTextField(title: "Commit message", text: $script.commitMessage)
            LabeledTextField(title: "PR title", text: $script.pullRequestTitle)
            LabeledTextEditor(title: "PR body", text: $script.pullRequestBody, minHeight: 110)
        }
    }

    private var runnerLabelsBinding: Binding<String> {
        Binding(
            get: { script.runnerLabels.joined(separator: ", ") },
            set: { script.runnerLabels = parseLabels($0) }
        )
    }

    private func parseLabels(_ value: String) -> [String] {
        value
            .split(separator: ",")
            .map { String($0).trimmed }
            .filter { !$0.isEmpty }
    }
}

struct LabeledTextField: View {
    let title: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField(title, text: $text)
                .textFieldStyle(.roundedBorder)
        }
    }
}

struct LabeledTextEditor: View {
    let title: String
    @Binding var text: String
    var minHeight: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextEditor(text: $text)
                .font(.system(size: 12, design: .monospaced))
                .frame(minHeight: minHeight)
                .padding(4)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.12))
                )
        }
    }
}
