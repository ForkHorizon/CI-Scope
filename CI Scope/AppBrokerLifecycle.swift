import AppKit
import SwiftUI

/// Ties the broker's lifetime to the app: kickstart it on launch, touch a
/// heartbeat every few seconds while running, and delete the heartbeat on quit
/// so the broker drains its in-flight jobs and exits. Closing the last window
/// quits the app, which stops the broker.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var heartbeatTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Write the heartbeat before the broker's first check so it doesn't
        // immediately think the app is gone and drain on startup.
        LocalBrokerService(config: DashboardConfig()).writeAppHeartbeat()
        Task {
            _ = try? await LocalBrokerService(config: DashboardConfig()).installOrUpdateLaunchAgent()
        }
        let timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            LocalBrokerService(config: DashboardConfig()).writeAppHeartbeat()
        }
        RunLoop.main.add(timer, forMode: .common)
        heartbeatTimer = timer
    }

    func applicationWillTerminate(_ notification: Notification) {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        // Drain signal: the broker finishes in-flight jobs, then exits.
        LocalBrokerService(config: DashboardConfig()).clearAppHeartbeat()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
