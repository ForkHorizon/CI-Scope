import AppKit
import SwiftUI

struct JobNotificationOverlay: View {
    @ObservedObject var manager: NotificationManager

    var body: some View {
        if let notification = manager.activeJobNotification {
            JobNotificationBanner(notification: notification) {
                manager.dismissJobNotification(id: notification.id)
            }
            .padding(.top, 12)
            .padding(.trailing, 14)
            .transition(.move(edge: .top).combined(with: .opacity))
            .task(id: notification.id) {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await MainActor.run {
                    manager.dismissJobNotification(id: notification.id)
                }
            }
        }
    }
}

private struct JobNotificationBanner: View {
    let notification: JobArrivalNotification
    let onDismiss: () -> Void

    var body: some View {
        GlassEffectContainer {
            VStack(alignment: .leading, spacing: 10) {
                header

                if let firstJob = notification.newJobs.first {
                    JobNotificationPrimaryLine(job: firstJob, count: notification.newJobs.count)
                }

                if shouldShowWorkList {
                    Divider()
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            if !notification.runningJobs.isEmpty {
                                JobNotificationSection(title: "Running Now", jobs: notification.runningJobs, tint: .green)
                            }

                            if !notification.queuedJobs.isEmpty {
                                JobNotificationSection(
                                    title: "Queue",
                                    jobs: Array(notification.queuedJobs.prefix(5)),
                                    tint: .orange
                                )

                                if notification.queuedJobs.count > 5 {
                                    Text("+\(notification.queuedJobs.count - 5) more queued")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .trailing)
                                }
                            }
                        }
                    }
                    .scrollIndicators(.never)
                    .frame(maxHeight: 188)
                }
            }
            .padding(13)
            .frame(width: 372, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 8))
            .shadow(color: Color.black.opacity(0.18), radius: 18, y: 10)
        }
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "tray.full")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 1) {
                Text(notification.newJobs.count == 1 ? "New CI Job" : "New CI Jobs")
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text(notification.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.glass)
            .help("Dismiss")
        }
    }

    private var shouldShowWorkList: Bool {
        !notification.runningJobs.isEmpty || !notification.queuedJobs.isEmpty
    }
}

private struct JobNotificationPrimaryLine: View {
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
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text("\(job.workflowName) · \(job.jobName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private var primaryText: String {
        count == 1 ? job.repositorySlug : "\(job.repositorySlug) and \(count - 1) more"
    }
}

private struct JobNotificationSection: View {
    let title: String
    let jobs: [RunnerWorkItem]
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            ForEach(jobs) { job in
                JobNotificationJobRow(job: job, tint: tint)
            }
        }
    }
}

private struct JobNotificationJobRow: View {
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
