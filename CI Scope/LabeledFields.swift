import SwiftUI

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
