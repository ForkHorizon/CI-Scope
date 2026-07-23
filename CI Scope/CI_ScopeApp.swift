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

/// The broker is a persistent LaunchAgent. It continues an accepted GitHub
/// Actions job when the dashboard is closed, rebuilt, or force-quit.
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
}
