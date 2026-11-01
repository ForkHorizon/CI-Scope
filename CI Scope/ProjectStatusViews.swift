import SwiftUI

struct ErrorBox: View {
    let text: String

    var body: some View {
        Text(text)
            .font(NothingTheme.tiny.monospaced())
            .foregroundStyle(NothingTheme.red)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(NothingTheme.red.opacity(0.5), lineWidth: 1))
    }
}

struct LimitedStatusRow: View {
    let title: String
    let value: String
    let state: ServiceState

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(NothingTheme.body.weight(.semibold))
                    .lineLimit(1)
                Text(value)
                    .font(NothingTheme.small)
                    .foregroundStyle(NothingTheme.inkDim)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()
            StatusDot(state: state)
        }
        .nothingRow()
    }
}
