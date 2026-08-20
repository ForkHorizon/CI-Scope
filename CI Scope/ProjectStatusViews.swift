import SwiftUI

struct ErrorBox: View {
  let text: String

  var body: some View {
    Text(text)
      .font(.caption2.monospaced())
      .foregroundStyle(.red)
      .textSelection(.enabled)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(9)
      .background(Color.red.opacity(0.08))
      .clipShape(RoundedRectangle(cornerRadius: 7))
      .overlay(
        RoundedRectangle(cornerRadius: 7)
          .stroke(Color.red.opacity(0.18))
      )
  }
}

struct LimitedStatusRow: View {
  let title: String
  let value: String
  let icon: String
  let state: ServiceState

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: icon)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.secondary)
        .frame(width: 18)

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.callout.weight(.semibold))
          .lineLimit(1)
        Text(value)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
      }

      Spacer()
      StatusDot(state: state)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 7)
    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    .background(Color.secondary.opacity(0.055))
    .clipShape(RoundedRectangle(cornerRadius: 7))
  }
}
