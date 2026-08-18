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

/// The UI is not the owner of runner processes. Quitting only releases the
/// UI's control lease; the Agent decides whether to drain and active jobs keep
/// running. A crash or force-quit has the same safety property because no
/// destructive cleanup is performed from the app lifecycle callback.
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
        return .terminateNow
    }
}
