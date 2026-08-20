import AppKit
import SwiftUI

struct RunnerWarningLine: View {
  let text: String

  var body: some View {
    HStack(spacing: 7) {
      Image(systemName: "exclamationmark.triangle")
        .foregroundStyle(.orange)
      Text(text)
        .font(.caption)
        .foregroundStyle(.orange)
        .lineLimit(2)
      Spacer()
    }
    .padding(8)
    .background(Color.orange.opacity(0.08))
    .clipShape(RoundedRectangle(cornerRadius: 7))
  }
}
