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
        Group {
            VStack(alignment: .leading, spacing: 10) {
                header

                if let firstJob = notification.newJobs.first {
                    JobNotificationPrimaryLine(job: firstJob, count: notification.newJobs.count)
                }

                if shouldShowWorkList {
                    Divider()
                    do {
                        VStack(alignment: .leading, spacing: 10) {
                            if !notification.runningJobs.isEmpty {
                                JobNotificationSection(
                                    title: "Running Now", jobs: Array(notification.runningJobs.prefix(3)), tint: NothingTheme.green)
                            }

                            if !notification.queuedJobs.isEmpty {
                                JobNotificationSection(
                                    title: "Queue",
                                    jobs: Array(notification.queuedJobs.prefix(3)),
                                    tint: NothingTheme.amber
                                )

                                if notification.queuedJobs.count > 3 {
                                    Text("+\(notification.queuedJobs.count - 3) more queued")
                                        .font(NothingTheme.tiny)
                                        .foregroundStyle(NothingTheme.inkDim)
                                        .frame(maxWidth: .infinity, alignment: .trailing)
                                }
                            }
                        }
                    }
                }
            }
            .padding(13)
            .frame(width: 340, alignment: .leading)
            .background(Color(white: 0.04), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(NothingTheme.lineStrong, lineWidth: 1))
            .shadow(color: Color.black.opacity(0.5), radius: 20, y: 10)
        }
    }

    private var header: some View {
        HStack(spacing: 9) {
            Circle().fill(NothingTheme.amber).frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 1) {
                Text(notification.newJobs.count == 1 ? "New CI Job" : "New CI Jobs")
                    .font(NothingTheme.body.weight(.semibold))
                    .lineLimit(1)
                Text(notification.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(NothingTheme.tiny.monospacedDigit())
                    .foregroundStyle(NothingTheme.inkDim)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
                    .frame(width: 26, height: 26)
                    .overlay(Circle().stroke(NothingTheme.lineStrong, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
    }

    private var shouldShowWorkList: Bool {
        !notification.runningJobs.isEmpty || !notification.queuedJobs.isEmpty
    }
}
