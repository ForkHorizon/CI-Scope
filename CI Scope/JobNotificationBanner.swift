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
                                JobNotificationSection(
                                    title: "Running Now", jobs: notification.runningJobs, tint: .green)
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
