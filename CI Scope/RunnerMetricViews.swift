import SwiftUI

struct RunnerMiniMetric: View {
  let title: String
  let value: String

  var body: some View {
    HStack(spacing: 4) {
      Text(title)
        .font(.caption2)
        .foregroundStyle(.secondary)
      Text(value)
        .font(.caption2.monospacedDigit().weight(.semibold))
    }
  }
}

struct RunnerMetric: View {
  let title: String
  let value: String
  let detail: String
  let state: ServiceState

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 5) {
        Circle()
          .fill(color(for: state))
          .frame(width: 6, height: 6)
        Text(title)
          .font(.caption2.weight(.semibold))
          .lineLimit(1)
      }
      Text(value)
        .font(.caption.weight(.semibold))
        .lineLimit(1)
        .truncationMode(.middle)
      Text(detail)
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .truncationMode(.middle)
    }
    .padding(8)
    .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
    .background(Color.secondary.opacity(0.055))
    .clipShape(RoundedRectangle(cornerRadius: 7))
  }
}
