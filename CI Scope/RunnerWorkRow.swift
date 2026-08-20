import AppKit
import SwiftUI

struct RunnerWorkRow: View {
  let item: RunnerWorkItem

  var body: some View {
    HStack(spacing: 9) {
      Circle()
        .fill(item.status == "queued" ? Color.orange : Color.green)
        .frame(width: 8, height: 8)

      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 6) {
          Text(item.repositorySlug)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .truncationMode(.middle)
          Text(item.status)
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
          if let assemblerTitle = item.assemblerTitle {
            Text(assemblerTitle)
              .font(.caption2.weight(.semibold))
              .lineLimit(1)
              .truncationMode(.tail)
              .padding(.horizontal, 5)
              .frame(height: 16)
              .background(Color.accentColor.opacity(0.1))
              .foregroundStyle(Color.accentColor)
              .clipShape(RoundedRectangle(cornerRadius: 5))
              .help(item.assemblerScope ?? assemblerTitle)
          }
        }

        Text("\(item.workflowName) · \(item.jobName)")
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)

        Text("\(item.title) · \(item.headBranch)")
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)

        if let progress = item.progress {
          Text(progress.caption)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
        }
      }

      Spacer(minLength: 8)

      if let url = URL(string: item.url), !item.url.isEmpty {
        Button {
          NSWorkspace.shared.open(url)
        } label: {
          Image(systemName: "arrow.up.right.square")
            .font(.system(size: 12, weight: .semibold))
            .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .help("Open GitHub job")
      }
    }
    .padding(.horizontal, 9)
    .padding(.vertical, 8)
    .background(Color.secondary.opacity(0.055))
    .clipShape(RoundedRectangle(cornerRadius: 7))
  }
}

struct RunnerLabelStrip: View {
  let labels: [String]

  var body: some View {
    if !labels.isEmpty {
      HStack(spacing: 5) {
        ForEach(labels.prefix(8), id: \.self) { label in
          Text(label)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .frame(height: 18)
            .background(Color.secondary.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }

        if labels.count > 8 {
          Text("+\(labels.count - 8)")
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
        }
      }
    }
  }
}
