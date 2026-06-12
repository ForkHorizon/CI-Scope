import Foundation
import Combine
import UserNotifications

@MainActor
final class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    @Published private(set) var activeJobNotification: JobArrivalNotification?

    private var previousRuns: [String: String] = [:]
    private var previousRunners: [String: ServiceState] = [:]
    private var previousWorkItemIDs: Set<String> = []
    private var hasRequestedPermission = false
    private var fetchedProjects: Set<String> = []
    private var fetchedRunnerSnapshots = false
    private var fetchedWorkSnapshot = false

    private init() {
        Task {
            await requestAuthorization()
        }
    }

    private func requestAuthorization() async {
        guard !hasRequestedPermission else { return }
        hasRequestedPermission = true
        do {
            try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        } catch {
            print("Failed to request notification authorization: \(error)")
        }
    }

    func checkRunUpdates(projectSlug: String, runs: [GitHubRun]) {
        let isInitialFetch = !fetchedProjects.contains(projectSlug)

        for run in runs {
            let runKey = "\(projectSlug)-\(run.id)"
            let previousStatus = previousRuns[runKey]

            if !isInitialFetch {
                // If it wasn't seen before, or it was seen as something other than completed, and now it is completed
                if previousStatus != "completed" && run.status == "completed" {
                    sendRunNotification(projectSlug: projectSlug, run: run)
                }
            }

            previousRuns[runKey] = run.status
        }

        fetchedProjects.insert(projectSlug)
    }

    func checkWorkUpdates(snapshot: RunnerFleetSnapshot) {
        let isInitialFetch = !fetchedWorkSnapshot
        let activeJobs = uniqueWorkItems(snapshot.runners.flatMap(\.activeJobs))
        let activeIDs = Set(activeJobs.map(\.id))
        let queuedJobs = uniqueWorkItems(snapshot.runners.flatMap(\.queuedJobs))
            .filter { !activeIDs.contains($0.id) }
        let visibleJobs = activeJobs + queuedJobs
        let currentIDs = Set(visibleJobs.map(\.id))
        let newJobs = visibleJobs.filter { !previousWorkItemIDs.contains($0.id) }

        defer {
            previousWorkItemIDs = currentIDs
            fetchedWorkSnapshot = true
        }

        // On the first snapshot every running/queued job looks "new"; don't fire
        // notifications for work already in flight before the app started
        // (mirrors checkRunUpdates / checkRunnerUpdates).
        guard !newJobs.isEmpty, !isInitialFetch else { return }

        let notification = JobArrivalNotification(
            newJobs: newJobs,
            runningJobs: activeJobs,
            queuedJobs: queuedJobs
        )
        activeJobNotification = notification
        sendJobNotification(notification)
    }

    func dismissJobNotification(id: String) {
        guard activeJobNotification?.id == id else { return }
        activeJobNotification = nil
    }

    func checkRunnerUpdates(runners: [RunnerMonitorSnapshot]) {
        for runner in runners {
            let previousState = previousRunners[runner.id]

            if fetchedRunnerSnapshots {
                if previousState == .online && runner.state == .offline {
                    sendRunnerNotification(runnerName: runner.title, state: runner.state)
                }
            }

            previousRunners[runner.id] = runner.state
        }
        fetchedRunnerSnapshots = true
    }

    private func sendRunNotification(projectSlug: String, run: GitHubRun) {
        let content = UNMutableNotificationContent()

        var statusIcon = ""
        var conclusionText = ""

        if run.conclusion == "success" {
            statusIcon = "✅"
            conclusionText = "Succeeded"
        } else if run.conclusion == "failure" {
            statusIcon = "❌"
            conclusionText = "Failed"
        } else {
            statusIcon = "⚠️"
            conclusionText = run.conclusion?.capitalized ?? "Completed"
        }

        content.title = "\(statusIcon) Workflow \(conclusionText)"
        content.subtitle = projectSlug
        content.body = "\(run.workflowName): \(run.displayTitle)"
        content.sound = UNNotificationSound.default

        let request = UNNotificationRequest(identifier: "run-\(run.id)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func sendJobNotification(_ notification: JobArrivalNotification) {
        guard let firstJob = notification.newJobs.first else { return }

        let content = UNMutableNotificationContent()
        content.title =
            notification.newJobs.count == 1
            ? "New CI job"
            : "\(notification.newJobs.count) new CI jobs"
        content.subtitle = firstJob.repositorySlug

        if notification.newJobs.count == 1 {
            content.body = "\(firstJob.workflowName): \(firstJob.jobName)"
        } else {
            content.body = "\(firstJob.workflowName): \(firstJob.jobName) and \(notification.newJobs.count - 1) more"
        }
        content.sound = UNNotificationSound.default

        let identifier = "job-\(notification.id)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func sendRunnerNotification(runnerName: String, state: ServiceState) {
        let content = UNMutableNotificationContent()

        content.title = "⚠️ Runner Offline"
        content.body = "Runner \(runnerName) is now offline."
        content.sound = UNNotificationSound.default

        let identifier = "runner-\(runnerName)-\(Date().timeIntervalSince1970)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func uniqueWorkItems(_ items: [RunnerWorkItem]) -> [RunnerWorkItem] {
        var seen: Set<String> = []
        var result: [RunnerWorkItem] = []
        for item in items {
            guard !seen.contains(item.id) else { continue }
            seen.insert(item.id)
            result.append(item)
        }
        return result
    }
}
