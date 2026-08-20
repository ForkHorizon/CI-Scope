import AppKit
import SwiftUI

struct JobNotificationJobRow: View {
  let job: RunnerWorkItem
  let tint: Color

  var body: some View {
    HStack(spacing: 8) {
      Circle()
        .fill(tint)
        .frame(width: 7, height: 7)

      VStack(alignment: .leading, spacing: 2) {
        Text(job.repositorySlug)
          .font(.caption.weight(.semibold))
          .lineLimit(1)
          .truncationMode(.middle)

        Text("\(job.workflowName) · \(job.jobName)")
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
      }

      Spacer(minLength: 6)

      if let url = URL(string: job.url), !job.url.isEmpty {
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
    .padding(.vertical, 7)
    .background(Color.secondary.opacity(0.075))
    .clipShape(RoundedRectangle(cornerRadius: 7))
  }
}
