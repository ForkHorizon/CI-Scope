import AppKit
import SwiftUI

struct RunnerEmptyState: View {
  var body: some View {
    VStack(spacing: 8) {
      Image(systemName: "server.rack")
        .font(.title3)
        .foregroundStyle(.secondary)
      Text("No runner loaded")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, minHeight: 180)
  }
}
