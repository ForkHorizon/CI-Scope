import Foundation
import UserNotifications

@MainActor
final class NotificationManager {
    static let shared = NotificationManager()

    private var previousRuns: [String: String] = [:]
    private var previousRunners: [String: ServiceState] = [:]
    private var hasRequestedPermission = false
    private var fetchedProjects: Set<String> = []
    private var fetchedRunnerSnapshots = false
    private var fetchedDashboardRunner = false

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

    func checkDashboardRunnerUpdate(runner: RunnerStatus) {
        let runnerId = "local-runner"
        let previousState = previousRunners[runnerId]

        if fetchedDashboardRunner {
            if previousState == .online && runner.state == .offline {
                sendRunnerNotification(runnerName: "Local Runner", state: runner.state)
            }
        }

        previousRunners[runnerId] = runner.state
        fetchedDashboardRunner = true
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

    private func sendRunnerNotification(runnerName: String, state: ServiceState) {
        let content = UNMutableNotificationContent()

        content.title = "⚠️ Runner Offline"
        content.body = "Runner \(runnerName) is now offline."
        content.sound = UNNotificationSound.default

        let identifier = "runner-\(runnerName)-\(Date().timeIntervalSince1970)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
