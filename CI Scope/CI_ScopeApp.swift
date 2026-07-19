//
//  CI_ScopeApp.swift
//  CI Scope
//
//  Created by Kiryl Shcherba on 27/05/2026.
//

import AppKit
import SwiftUI

@main
struct CI_ScopeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

/// Tears the broker down when the app quits normally, so its LaunchAgent and
/// any runner it's mid-job on don't outlive the app. A crash or force-quit
/// skips this entirely — the broker's own CI_SCOPE_APP_PID watchdog
/// (see LocalBrokerLaunchAgent) is what catches that case.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hard crashes (force-unwrap, trap) aren't catchable in-process — macOS's
        // crash reporter already covers those in ~/Library/Logs/DiagnosticReports.
        // This only catches the one class Cocoa lets you intercept.
        NSSetUncaughtExceptionHandler { exception in
            AppLogger.shared.crash(
                "process.crash",
                "Uncaught exception: \(exception.name.rawValue) — \(exception.reason ?? "no reason")",
                context: ["callStack": exception.callStackSymbols.joined(separator: "\n")]
            )
        }
        AppLogger.shared.info("app.launch", "CI Scope launched", context: ["pid": ProcessInfo.processInfo.processIdentifier])
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        AppLogger.shared.info("app.quit", "CI Scope quitting")
        Task {
            await LocalBrokerService(config: DashboardConfig()).uninstallLaunchAgent()
            await MainActor.run {
                sender.reply(toApplicationShouldTerminate: true)
            }
        }
        return .terminateLater
    }
}
