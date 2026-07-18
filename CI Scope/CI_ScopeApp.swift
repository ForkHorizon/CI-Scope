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
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task {
            await LocalBrokerService(config: DashboardConfig()).uninstallLaunchAgent()
            await MainActor.run {
                sender.reply(toApplicationShouldTerminate: true)
            }
        }
        return .terminateLater
    }
}
