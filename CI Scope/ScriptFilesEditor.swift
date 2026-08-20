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
      Button {
        script.files.append(.empty())
      } label: {
        Label("Add File", systemImage: "plus")
      }
      .buttonStyle(.bordered)
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
          .textFieldStyle(.roundedBorder)
        Toggle("Executable", isOn: $file.isExecutable)
        Button(role: .destructive, action: onRemove) {
          Image(systemName: "trash")
        }
      }

      TextEditor(text: $file.contents)
        .font(.system(size: 11, design: .monospaced))
        .frame(minHeight: 220)
        .padding(4)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
          RoundedRectangle(cornerRadius: 6)
            .stroke(Color.secondary.opacity(0.12))
        )
    }
    .padding(9)
    .background(Color.secondary.opacity(0.055))
    .clipShape(RoundedRectangle(cornerRadius: 7))
  }
}
