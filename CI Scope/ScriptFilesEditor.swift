import SwiftUI

struct ScriptFilesEditor: View {
    @Binding var script: AutomationScript

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach($script.files) { $file in
                ScriptFileCard(file: $file) {
                    remove(file)
                }
            }
            Button("Add file") { script.files.append(.empty()) }
                .buttonStyle(.pill)
        }
    }

    private func remove(_ file: AutomationScriptFile) {
        script.files.removeAll { $0.id == file.id }
    }
}

struct ScriptFileCard: View {
    @Binding var file: AutomationScriptFile
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("destination/path", text: $file.destinationPath)
                    .font(.system(size: 12, design: .monospaced))
                    .nothingField()
                Toggle("Executable", isOn: $file.isExecutable)
                Button("Remove", action: onRemove).buttonStyle(.pillDanger)
            }

            TextEditor(text: $file.contents)
                .font(.system(size: 11, design: .monospaced))
                .frame(minHeight: 220)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(NothingTheme.panel, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(NothingTheme.line, lineWidth: 1))
        }
        .padding(12)
        .nothingCard(radius: 12)
    }
}
