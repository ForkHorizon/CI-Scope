import Foundation

enum AutomationScriptVariableKind: String, Codable, CaseIterable, Identifiable {
    case text
    case multiline
    case boolean
    case number
    case option

    var id: String { rawValue }

    var title: String {
        switch self {
        case .text: "Text"
        case .multiline: "Multiline"
        case .boolean: "Boolean"
        case .number: "Number"
        case .option: "Option"
        }
    }
}

struct AutomationScriptVariable: Identifiable, Codable, Equatable {
    var id: String
    var title: String
    var kind: AutomationScriptVariableKind
    var isRequired: Bool
    var defaultValue: String
    var help: String
    var options: [String]

    static func empty() -> AutomationScriptVariable {
        AutomationScriptVariable(
            id: "variable",
            title: "Variable",
            kind: .text,
            isRequired: false,
            defaultValue: "",
            help: "",
            options: []
        )
    }
}

struct AutomationScriptFile: Identifiable, Codable, Equatable {
    var id: String
    var destinationPath: String
    var isExecutable: Bool
    var contents: String

    static func empty() -> AutomationScriptFile {
        AutomationScriptFile(
            id: UUID().uuidString,
            destinationPath: "scripts/new-script.sh",
            isExecutable: true,
            contents: "#!/usr/bin/env bash\nset -euo pipefail\n"
        )
    }
}

struct AutomationScript: Identifiable, Codable, Equatable {
    var id: String
    var title: String
    var summary: String
    var detail: String
    var runnerLabels: [String]
    var branchName: String
    var commitMessage: String
    var pullRequestTitle: String
    var pullRequestBody: String
    var variables: [AutomationScriptVariable]
    var files: [AutomationScriptFile]
    var defaultSeedID: String?

    static func empty(uniqueID: String) -> AutomationScript {
        AutomationScript(
            id: uniqueID,
            title: "New Script",
            summary: "Custom automation script.",
            detail: "",
            runnerLabels: ["self-hosted", "macOS", "ARM64", "ci-scope"],
            branchName: "ci-scope/install-{{script_id}}",
            commitMessage: "Add {{script_id}} automation",
            pullRequestTitle: "Add {{script_id}} automation",
            pullRequestBody: "Adds {{script_id}} automation managed by CI Scope.",
            variables: [],
            files: [.empty()],
            defaultSeedID: nil
        )
    }
}

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
