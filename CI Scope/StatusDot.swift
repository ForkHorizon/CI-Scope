import AppKit
import SwiftUI

struct StatusDot: View {
  let state: ServiceState

  var body: some View {
    Circle()
      .fill(color)
      .frame(width: 8, height: 8)
      .overlay {
        Circle()
          .stroke(color.opacity(0.35), lineWidth: 3)
      }
      .help(state.rawValue)
  }

  var color: Color {
    switch state {
    case .online: .green
    case .warning: .orange
    case .offline: .red
    case .unknown: .secondary
    }
  }
}
