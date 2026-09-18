import Foundation

enum AutomationScriptInstallMode: String, CaseIterable, Identifiable {
    case localRunner
    case githubHosted

    static let allCases: [AutomationScriptInstallMode] = [.localRunner]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .localRunner: "MacBook Runner"
        case .githubHosted: "GitHub hosted"
        }
    }

    func detail(for script: AutomationScript?) -> String {
        switch self {
        case .localRunner: "Runs jobs on this Mac through the V2 Agent."
        case .githubHosted:
            if script?.requiresMacGitHubHostedRunner == true {
                "Uses GitHub-hosted macOS runners for Swift/Xcode scripts."
            } else {
                "Uses GitHub-hosted runners for portable scripts."
            }
        }
    }

    func runnerLabels(for script: AutomationScript?) -> [String] {
        switch self {
        case .localRunner: ["self-hosted", "macOS", "ARM64", "ci-scope", "ci-scope-v2"]
        case .githubHosted:
            script?.requiresMacGitHubHostedRunner == true ? ["macos-latest"] : ["ubuntu-latest"]
        }
    }
}

extension AutomationScript {
    fileprivate var requiresMacGitHubHostedRunner: Bool {
        defaultSeedID == "swift-quality-gate" || id == "swift-quality-gate"
    }
}
