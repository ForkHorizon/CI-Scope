import AppKit
import SwiftUI

struct PanelShell<Content: View>: View {
  let title: String
  let icon: String
  @ViewBuilder let content: Content

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Label(title, systemImage: icon)
          .font(.caption.weight(.semibold))
        Spacer()
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 8)
      .background(Color.secondary.opacity(0.055))
      Divider()
      content
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(nsColor: .controlBackgroundColor))
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .overlay(
      RoundedRectangle(cornerRadius: 8)
        .stroke(Color.secondary.opacity(0.13))
    )
  }
}

struct EmptyState: View {
  let icon: String
  let text: String

  var body: some View {
    VStack(spacing: 8) {
      Image(systemName: icon)
        .font(.title3)
        .foregroundStyle(.secondary)
      Text(text)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, minHeight: 120)
  }
}

#Preview {
  ContentView()
}
