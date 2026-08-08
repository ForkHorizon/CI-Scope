import Foundation

struct AutomationScriptInstallSnapshot: Equatable {
    var state: ServiceState
    var title: String
    var detail: String
    var isInstalling: Bool
    var pullRequestURL: URL?

    static let idle = AutomationScriptInstallSnapshot(
        state: .unknown,
        title: "No install run",
        detail: "Choose a project and install this script.",
        isInstalling: false,
        pullRequestURL: nil
    )

    static func installing(_ script: AutomationScript) -> AutomationScriptInstallSnapshot {
        AutomationScriptInstallSnapshot(
            state: .warning,
            title: "Installing \(script.title)",
            detail: "Creating branch, rendering files, and preparing a pull request.",
            isInstalling: true,
            pullRequestURL: nil
        )
    }

    static func installingBundle(count: Int) -> AutomationScriptInstallSnapshot {
        AutomationScriptInstallSnapshot(
            state: .warning,
            title: "Installing \(count) gate\(count == 1 ? "" : "s")",
            detail: "Rendering the recommended gates into one pull request.",
            isInstalling: true,
            pullRequestURL: nil
        )
    }

    static func removing(_ script: AutomationScript) -> AutomationScriptInstallSnapshot {
        AutomationScriptInstallSnapshot(
            state: .warning,
            title: "Removing \(script.title)",
            detail: "Creating branch, removing script files, and preparing a pull request.",
            isInstalling: true,
            pullRequestURL: nil
        )
    }

    static func succeeded(_ result: AutomationScriptInstallResult) -> AutomationScriptInstallSnapshot {
        AutomationScriptInstallSnapshot(
            state: .online,
            title: result.title,
            detail: result.detail,
            isInstalling: false,
            pullRequestURL: result.pullRequestURL
        )
    }

    static func failed(_ message: String) -> AutomationScriptInstallSnapshot {
        AutomationScriptInstallSnapshot(
            state: .offline,
            title: "Install failed",
            detail: message,
            isInstalling: false,
            pullRequestURL: nil
        )
    }
}

struct AutomationScriptInstallResult {
    let title: String
    let detail: String
    let pullRequestURL: URL?
}
