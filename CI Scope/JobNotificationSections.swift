import AppKit
import SwiftUI

struct JobNotificationPrimaryLine: View {
    let job: RunnerWorkItem
    let count: Int

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: count == 1 ? "bolt.fill" : "square.stack.3d.up")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(primaryText)
                    .font(NothingTheme.small.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text("\(job.workflowName) · \(job.jobName)")
                    .font(NothingTheme.small)
                    .foregroundStyle(NothingTheme.inkDim)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private var primaryText: String {
        count == 1 ? job.repositorySlug : "\(job.repositorySlug) and \(count - 1) more"
    }
}

struct JobNotificationSection: View {
    let title: String
    let jobs: [RunnerWorkItem]
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(NothingTheme.tiny.weight(.semibold))
                .foregroundStyle(NothingTheme.inkDim)
                .textCase(.uppercase)

            ForEach(jobs) { job in
                JobNotificationJobRow(job: job, tint: tint)
            }
        }
    }
}
