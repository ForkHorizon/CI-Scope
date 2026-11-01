import SwiftUI

struct LabeledTextField: View {
    let title: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(NothingTheme.small.weight(.semibold))
                .foregroundStyle(NothingTheme.inkDim)
            TextField(title, text: $text)
                .nothingField()
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
                .font(NothingTheme.small.weight(.semibold))
                .foregroundStyle(NothingTheme.inkDim)
            TextEditor(text: $text)
                .font(.system(size: 12, design: .monospaced))
                .frame(minHeight: minHeight)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(NothingTheme.panel, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(NothingTheme.line, lineWidth: 1))
        }
    }
}
